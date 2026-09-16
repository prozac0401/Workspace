using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace FolderState.Core;

public sealed class FolderStateEngine(string iconDirectory, string? logDirectory = null)
{
    public const string StateFile = ".folderstate.ini";
    public const string JournalFile = ".folderstate.transaction";
    private const string DesktopFile = "desktop.ini", PortableFile = ".folderstate.ico";
    private const FileAttributes HiddenSystem = FileAttributes.Hidden | FileAttributes.System;
    private static readonly string[] IconKeys = ["IconResource", "IconFile", "IconIndex"];
    // A deterministic fault seam for transaction tests; never configured by the shipped applications.
    public Action<string>? TransactionCheckpoint { private get; init; }

    public StateInfo? ReadState(string folder)
    {
        string target = SafeFiles.Folder(folder);
        using var gate = Acquire(target);
        if (SafeFiles.Read(Path.Combine(target, JournalFile), 4 * 1024 * 1024).Data is not null)
            throw new StateException("recovery_pending", "이전 작업이 끝나기 전에 멈췄습니다. ‘아이콘 다시 표시’를 실행해 주세요.");
        var metadata = ReadMetadata(SafeFiles.Read(Path.Combine(target, StateFile)));
        return metadata is null ? null : new(StateNames.Parse(metadata.Status), ParseMode(metadata.Mode), metadata.Updated);
    }
    public OperationResult Set(string folder, WorkStatus status, IconMode? mode = null) => Execute(folder, "set", status, mode);
    public OperationResult Repair(string folder) => Execute(folder, "repair", null, null);
    public OperationResult Reset(string folder) => Execute(folder, "reset", null, null);

    private OperationResult Execute(string folder, string action, WorkStatus? status, IconMode? mode)
    {
        string target = folder; string? previous = null; OperationResult result;
        try
        {
            target = SafeFiles.Folder(folder);
            using var gate = Acquire(target);
            Recover(target);
            var state = SafeFiles.Read(Path.Combine(target, StateFile));
            var metadata = ReadMetadata(state); previous = metadata?.Status;
            if (action == "repair" && metadata is null)
                throw new StateException("state_missing", "다시 표시할 상태가 없습니다. 먼저 ‘시작 전’, ‘진행 중’, ‘완료’, ‘확인 필요’ 중 하나를 선택해 주세요.");
            if (action == "reset" && metadata is null)
                result = new(true, action, target, null, null, "지울 상태 표시가 없습니다. 폴더는 그대로 두었습니다.");
            else
            {
                var desktop = SafeFiles.Read(Path.Combine(target, DesktopFile));
                var document = IniDocument.Read(desktop.Data);
                bool folderReadOnly = File.GetAttributes(target).HasFlag(FileAttributes.ReadOnly);
                var backup = metadata?.Backup ?? new Backup(desktop, folderReadOnly, [], null);
                string previousIcon = backup.PortableName ?? PortableFile;
                var portable = SafeFiles.Read(Path.Combine(target, previousIcon));
                var changes = new List<Change>(); string? warning = null, refreshIcon = null; bool afterReadOnly;
                if (action == "reset")
                {
                    if (backup.Extensions?.Count > 0 || IniDocument.Read(state.Data).HasOtherData(
                        new Dictionary<string, string[]>(StringComparer.OrdinalIgnoreCase) {
                            ["FolderState"] = ["Version", "Owner", "Status", "Updated", "Mode"], ["FolderStateBackup"] = ["Data"] }))
                        throw new StateException("metadata_conflict", "상태 파일에 다른 곳에서 추가한 정보가 있어 상태 표시를 지우지 않았습니다. 파일을 그대로 두고 지원을 요청해 주세요.");
                    Snapshot restored;
                    if (desktop.Data is not null && desktop.Data.AsSpan().SequenceEqual(backup.ManagedDesktop)) restored = backup.Desktop;
                    else if (desktop.Data is null) { restored = desktop; warning = "폴더의 아이콘 설정 파일(desktop.ini)이 이미 없어 다시 만들지 않았습니다."; }
                    else
                    {
                        var owned = IniDocument.Read(backup.ManagedDesktop);
                        var original = IniDocument.Read(backup.Desktop.Data);
                        foreach (string key in IconKeys)
                        {
                            if (document.Get(".ShellClassInfo", key) == owned.Get(".ShellClassInfo", key))
                                document.Set(".ShellClassInfo", key, original.Get(".ShellClassInfo", key));
                            else warning = "FolderState 밖에서 바꾼 아이콘 설정은 그대로 두었습니다.";
                        }
                        // External edits keep their file attributes and folder customization bit.
                        restored = desktop with { Data = document.Bytes() };
                    }
                    changes.Add(new(DesktopFile, desktop, restored));
                    if (backup.PortableHash is not null && portable.Data is not null)
                    {
                        EnsurePortableOwned(portable, backup.PortableHash);
                        changes.Add(new(previousIcon, portable, Snapshot.Missing));
                    }
                    changes.Add(new(StateFile, state, Snapshot.Missing));
                    afterReadOnly = SafeFiles.SameData(restored, backup.Desktop) ? backup.FolderReadOnly : folderReadOnly;
                    status = null;
                }
                else
                {
                    status ??= StateNames.Parse(metadata!.Status);
                    mode ??= metadata is null ? IconMode.Local : ParseMode(metadata.Mode);
                    string iconPath = Path.GetFullPath(Path.Combine(iconDirectory, status.Value.Value() + ".ico"));
                    var icon = SafeFiles.Read(iconPath);
                    if (icon.Data is null || icon.Data.Length < 22 || !icon.Data.AsSpan(0, 4).SequenceEqual(new byte[] { 0, 0, 1, 0 }))
                        throw new StateException("icon_missing", "아이콘 파일이 없거나 손상되었습니다. FolderState 설치 파일을 다시 열고 ‘프로그램 복구’를 눌러 주세요.");
                    if (iconPath.Contains('\r') || iconPath.Contains('\n') || iconPath.Contains('"'))
                        throw new StateException("invalid_icon_path", "설치된 아이콘의 파일 경로를 사용할 수 없습니다. FolderState 설치 위치를 확인해 주세요.");
                    if (metadata is not null && desktop.Data is not null)
                    {
                        var managed = IniDocument.Read(backup.ManagedDesktop);
                        foreach (var key in IconKeys)
                            if (document.Get(".ShellClassInfo", key) != managed.Get(".ShellClassInfo", key))
                                throw new StateException("icon_conflict", "FolderState 밖에서 폴더 아이콘이 바뀌었습니다. 현재 아이콘을 확인해 주세요. 상태 아이콘으로 바꾸려면 ‘상태 표시 지우기’를 누른 뒤 원하는 상태를 선택합니다.");
                    }
                    string? portableHash = backup.PortableHash;
                    string? portableName = null;
                    if (mode == IconMode.Portable)
                    {
                        if (portable.Data is not null) EnsurePortableOwned(portable, portableHash);
                        portableHash = Hash(icon.Data);
                        portableName = PortableName(portableHash);
                        var nextIcon = previousIcon == portableName ? portable : SafeFiles.Read(Path.Combine(target, portableName));
                        // Never adopt a coincidentally matching file that our metadata does not own.
                        if (nextIcon.Data is not null && previousIcon != portableName)
                            throw new StateException("portable_conflict", "아이콘을 저장할 위치에 같은 이름의 파일이 있습니다. 파일을 덮어쓰지 않고 작업을 멈췄습니다. 파일을 지우지 말고 사용 안내의 오류 해결을 확인해 주세요.");
                        changes.Add(new(portableName, nextIcon, new(icon.Data, HiddenSystem)));
                        if (previousIcon != portableName && portable.Data is not null)
                            changes.Add(new(previousIcon, portable, Snapshot.Missing));
                    }
                    else if (portableHash is not null)
                    {
                        if (portable.Data is not null)
                        { EnsurePortableOwned(portable, portableHash); changes.Add(new(previousIcon, portable, Snapshot.Missing)); }
                        portableHash = null;
                    }
                    refreshIcon = mode == IconMode.Portable ? portableName : iconPath;
                    document.Set(".ShellClassInfo", "IconResource", refreshIcon + ",0");
                    document.Set(".ShellClassInfo", "IconFile", null);
                    document.Set(".ShellClassInfo", "IconIndex", null);
                    byte[] managedDesktop = document.Bytes();
                    backup = backup with { ManagedDesktop = managedDesktop, PortableHash = portableHash, PortableName = portableName };
                    metadata = new(2, "FolderState", status.Value.Value(), mode.Value.ToString().ToLowerInvariant(),
                        action == "repair" ? metadata!.Updated : DateTimeOffset.Now, backup);
                    var encodedState = WriteMetadata(metadata, state.Data);
                    if (encodedState.Length > SafeFiles.MaxBytes) throw new StateException("metadata_too_large", "기존 설정의 크기가 너무 커서 되돌릴 때 쓸 정보를 저장할 수 없습니다. 설정 파일을 지우지 말고 지원을 요청해 주세요.");
                    changes.Add(new(DesktopFile, desktop, new(managedDesktop, desktop.Attributes | HiddenSystem)));
                    changes.Add(new(StateFile, state, new(encodedState, state.Attributes | HiddenSystem)));
                    afterReadOnly = true;
                }
                var customizationWarning = Commit(target, new(2, "FolderState", folderReadOnly, afterReadOnly, changes.ToArray()), refreshIcon);
                // State has committed. A Shell failure must never report that the state write failed.
                var refreshWarning = ShellRefresh.Notify(target);
                warning = string.Join(" ", new[] { warning, customizationWarning, refreshWarning }.Where(s => s is not null));
                if (warning.Length == 0) warning = null;
                result = new(true, action, target, previous, status?.Value(), action switch
                { "reset" => "상태 표시를 지웠습니다. 폴더 이름과 업무 파일은 그대로입니다.", "repair" => "저장된 상태의 아이콘을 다시 표시하도록 설정했습니다. 아직 안 보이면 탐색기에서 F5를 눌러 주세요.", _ => $"‘{status!.Value.Label()}’으로 저장했습니다. 폴더 아이콘이 아직 안 바뀌면 탐색기에서 F5를 눌러 주세요." }, Warning: warning);
            }
        }
        catch (Exception ex) when (ex is not OutOfMemoryException)
        {
            var (code, message) = Describe(ex);
            result = new(false, action, target, previous, status?.Value(), message, code);
        }
        try { if (logDirectory is not null) WriteLog(logDirectory, result); }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or StateException)
        { result = result with { Warning = string.Join(" ", new[] { result.Warning, "이 PC에 작업 기록을 저장하지 못했습니다. 위에 표시된 작업 결과를 확인해 주세요." }.Where(s => s is not null)) }; }
        return result;
    }
    private string? Commit(string target, Transaction transaction, string? refreshIcon)
    {
        string journal = Path.Combine(target, JournalFile);
        byte[] bytes = JsonSerializer.SerializeToUtf8Bytes(transaction, StateNames.Json);
        using (var stream = new FileStream(journal, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough))
        { stream.Write(bytes); stream.Flush(true); }
        try
        {
            File.SetAttributes(journal, HiddenSystem);
            TransactionCheckpoint?.Invoke("journal");
            foreach (var change in transaction.Changes)
            { SafeFiles.Write(Path.Combine(target, change.Name), change.Before, change.After); TransactionCheckpoint?.Invoke(change.Name); }
            string? warning = null;
            if (refreshIcon is not null)
            {
                var desired = transaction.Changes.Single(c => c.Name == DesktopFile).After;
                // Check immediately before asking Shell to re-assert the same owned field.
                if (!SafeFiles.SameData(SafeFiles.Read(Path.Combine(target, DesktopFile)), desired))
                    throw new StateException("concurrent_edit", "작업 중에 폴더 설정이 바뀌어 작업을 멈췄습니다. 설정 파일을 지우지 말고 바뀐 내용을 확인해 주세요.");
                warning = ShellRefresh.UpdateIcon(target, refreshIcon);
                if (!SafeFiles.SameData(SafeFiles.Read(Path.Combine(target, DesktopFile)), desired))
                    throw new StateException("shell_metadata_changed", "Windows가 폴더 설정을 예상과 다르게 바꿔 작업을 멈췄습니다. 설정 파일과 작업 기록을 지우지 말고 지원을 요청해 주세요.");
                TransactionCheckpoint?.Invoke("shell");
            }
            SetReadOnly(target, transaction.AfterReadOnly);
            TransactionCheckpoint?.Invoke("attributes");
            File.Delete(journal);
            return warning;
        }
        catch (Exception operationError)
        {
            try { Recover(target); }
            catch (Exception recoveryError)
            { throw new StateException("recovery_failed", $"변경을 끝내지 못했고 이전 상태로도 되돌리지 못했습니다. 되돌릴 때 쓸 파일은 남겨 두었습니다. 파일을 지우지 말고 사용 안내의 오류 해결을 확인해 주세요.\n오류 정보: {operationError.GetType().Name}/{recoveryError.GetType().Name}"); }
            throw;
        }
    }
    private static void Recover(string target)
    {
        string journal = Path.Combine(target, JournalFile);
        var file = SafeFiles.Read(journal, 4 * 1024 * 1024);
        if (file.Data is null) return;
        Transaction transaction;
        try
        {
            transaction = JsonSerializer.Deserialize<Transaction>(file.Data, StateNames.Json) ?? throw new JsonException();
            if (transaction.Version is not (1 or 2) || transaction.Owner != "FolderState" || transaction.Changes is null || transaction.Changes.Length < 1 || transaction.Changes.Length > (transaction.Version == 1 ? 3 : 4) ||
                transaction.Changes.Select(c => c.Name).Distinct(StringComparer.OrdinalIgnoreCase).Count() != transaction.Changes.Length ||
                transaction.Changes.Any(c => !(c.Name is StateFile or DesktopFile or PortableFile || transaction.Version == 2 && ValidPortableName(c.Name)) || !ValidSnapshot(c.Before) || !ValidSnapshot(c.After)))
                throw new JsonException();
        }
        catch (Exception ex) when (ex is JsonException or NullReferenceException)
        { throw new StateException("invalid_journal", "중단된 작업을 되돌리는 데 필요한 파일이 손상되었습니다. 폴더 안의 설정 파일을 지우지 말고 지원을 요청해 주세요."); }
        var current = transaction.Changes.Select(c => SafeFiles.Read(Path.Combine(target, c.Name))).ToArray();
        for (int i = 0; i < current.Length; i++)
            if (!SafeFiles.SameData(current[i], transaction.Changes[i].Before) && !SafeFiles.SameData(current[i], transaction.Changes[i].After))
                throw new StateException("recovery_conflict", "작업이 멈춘 뒤 폴더 설정이 바뀌어 이전 상태로 되돌리지 않았습니다. 설정 파일을 지우지 말고 바뀐 내용을 확인해 주세요.");
        for (int i = transaction.Changes.Length - 1; i >= 0; i--)
            SafeFiles.Write(Path.Combine(target, transaction.Changes[i].Name), current[i], transaction.Changes[i].Before);
        SetReadOnly(target, transaction.BeforeReadOnly); File.Delete(journal);
    }
    private static bool ValidSnapshot(Snapshot? s) => s is not null && (s.Extensions?.Count ?? 0) == 0 && (s.Data?.Length ?? 0) <= SafeFiles.MaxBytes &&
        (s.Attributes & (FileAttributes.Directory | FileAttributes.ReparsePoint)) == 0;
    private static void SetReadOnly(string folder, bool enabled)
    {
        var attributes = File.GetAttributes(folder);
        var desired = enabled ? attributes | FileAttributes.ReadOnly : attributes & ~FileAttributes.ReadOnly;
        if (attributes != desired) File.SetAttributes(folder, desired);
    }
    private static string Hash(byte[] bytes) => Convert.ToHexString(SHA256.HashData(bytes));
    private static string PortableName(string hash) => ".folderstate-" + hash.ToLowerInvariant() + ".ico";
    private static bool ValidPortableName(string? name) => name is not null && name.Length == 81 &&
        name.StartsWith(".folderstate-", StringComparison.Ordinal) && name.EndsWith(".ico", StringComparison.Ordinal) &&
        name.AsSpan(13, 64).IndexOfAnyExcept("0123456789abcdef") < 0;
    private static void EnsurePortableOwned(Snapshot portable, string? hash)
    {
        if (hash is null || portable.Data is null || Hash(portable.Data) != hash)
            throw new StateException("portable_conflict", "폴더 안의 아이콘 파일을 FolderState가 저장한 파일로 확인할 수 없습니다. 덮어쓰지 않고 작업을 멈췄습니다. 파일을 지우지 말고 사용 안내의 오류 해결을 확인해 주세요.");
    }
    private static IconMode ParseMode(string value) => value switch
    { "local" => IconMode.Local, "portable" => IconMode.Portable, _ => throw new StateException("invalid_metadata", "아이콘을 어디에 저장했는지 읽을 수 없습니다. 설정 파일을 지우지 말고 지원을 요청해 주세요.") };
    private static Metadata? ReadMetadata(Snapshot snapshot)
    {
        if (snapshot.Data is null) return null;
        try
        {
            var ini = IniDocument.Read(snapshot.Data);
            var version = ini.Get("FolderState", "Version");
            if (version is not ("1" or "2") || ini.Get("FolderState", "Owner") != "FolderState") throw new FormatException();
            var status = ini.Get("FolderState", "Status") ?? throw new FormatException(); _ = StateNames.Parse(status);
            var mode = ini.Get("FolderState", "Mode") ?? throw new FormatException(); _ = ParseMode(mode);
            var updated = DateTimeOffset.ParseExact(ini.Get("FolderState", "Updated")!, "O", System.Globalization.CultureInfo.InvariantCulture);
            var backup = JsonSerializer.Deserialize<Backup>(Convert.FromBase64String(ini.Get("FolderStateBackup", "Data")!), StateNames.Json) ?? throw new FormatException();
            if (!ValidSnapshot(backup.Desktop) || backup.ManagedDesktop is null || backup.ManagedDesktop.Length > SafeFiles.MaxBytes || backup.ManagedDesktop.Length == 0) throw new FormatException();
            if (backup.PortableHash is not null && (backup.PortableHash.Length != 64 || backup.PortableHash.AsSpan().IndexOfAnyExcept("0123456789ABCDEF") >= 0)) throw new FormatException();
            if (version == "1" && backup.PortableName is not null ||
                version == "2" && (mode == "portable" ? backup.PortableHash is null || !ValidPortableName(backup.PortableName) || backup.PortableName != PortableName(backup.PortableHash) : backup.PortableName is not null || backup.PortableHash is not null)) throw new FormatException();
            _ = IniDocument.Read(backup.Desktop.Data); _ = IniDocument.Read(backup.ManagedDesktop);
            return new(version == "1" ? 1 : 2, "FolderState", status, mode, updated, backup);
        }
        catch (Exception ex) when (ex is FormatException or JsonException or ArgumentException or StateException)
        { throw new StateException("invalid_metadata", "저장된 상태를 읽을 수 없습니다. 파일이 손상되었거나 이 버전에서 읽을 수 없는 형식입니다. 상태 파일을 지우지 말고 지원을 요청해 주세요."); }
    }
    private static byte[] WriteMetadata(Metadata data, byte[]? original)
    {
        var ini = IniDocument.Read(original);
        ini.Set("FolderState", "Version", data.Version.ToString(System.Globalization.CultureInfo.InvariantCulture));
        ini.Set("FolderState", "Owner", data.Owner);
        ini.Set("FolderState", "Status", data.Status);
        ini.Set("FolderState", "Updated", data.Updated.ToString("O", System.Globalization.CultureInfo.InvariantCulture));
        ini.Set("FolderState", "Mode", data.Mode);
        ini.Set("FolderStateBackup", "Data", Convert.ToBase64String(JsonSerializer.SerializeToUtf8Bytes(data.Backup, StateNames.Json)));
        return ini.Bytes();
    }
    private static IDisposable Acquire(string target)
    {
        var mutex = new Mutex(false, (OperatingSystem.IsWindows() ? @"Local\" : "") + "FolderState-" + Hash(Encoding.UTF8.GetBytes(target.ToUpperInvariant())));
        bool acquired;
        try { acquired = mutex.WaitOne(TimeSpan.FromSeconds(8)); }
        catch (AbandonedMutexException) { acquired = true; }
        if (!acquired) { mutex.Dispose(); throw new StateException("busy", "같은 폴더에서 다른 작업이 진행 중입니다. 잠시 후 다시 실행해 주세요."); }
        return new MutexLease(mutex);
    }
    private sealed class MutexLease(Mutex mutex) : IDisposable
    { public void Dispose() { mutex.ReleaseMutex(); mutex.Dispose(); } }
    public static (string Code, string Message) Describe(Exception error) => error switch
    {
        StateException e => (e.Code, e.Message),
        UnauthorizedAccessException => ("access_denied", "파일을 읽거나 저장할 수 없습니다. 해당 폴더의 접근 권한과 회사 보안 설정을 확인해 주세요."),
        PathTooLongException => ("path_too_long", "폴더 경로가 너무 길어 작업하지 못했습니다. 이 PC가 긴 경로를 지원하는지 관리 담당자에게 확인해 주세요."),
        IOException => ("io_error", "파일을 읽거나 저장하지 못했습니다. 다른 프로그램이 사용 중인지, 드라이브 연결과 남은 저장 공간에 문제가 없는지 확인해 주세요."),
        ArgumentException => ("invalid_path", "입력한 폴더 경로나 명령을 확인해 주세요. 명령줄 사용 예시는 사용 안내에 있습니다."),
        _ => ("unexpected_error", "작업을 끝내지 못했습니다. 작업 기록과 폴더에 접근할 수 있는지 확인해 주세요.")
    };
    private static void WriteLog(string directory, OperationResult result)
    {
        Directory.CreateDirectory(directory);
        using var gate = Acquire(Path.GetFullPath(directory));
        string file = Path.Combine(directory, "operations.jsonl");
        var existing = SafeFiles.Read(file, 8 * 1024 * 1024);
        if (existing.Data?.Length > 4 * 1024 * 1024)
        {
            string previous = Path.Combine(directory, "operations.previous.jsonl");
            _ = SafeFiles.Read(previous, 8 * 1024 * 1024); File.Move(file, previous, true);
        }
        File.AppendAllText(file, JsonSerializer.Serialize(new { timestamp = DateTimeOffset.Now, action = result.Action,
            target_path = result.TargetPath, previous_status = result.PreviousStatus, new_status = result.NewStatus,
            result = result.Success ? "success" : "failure", error = result.ErrorCode, message = result.Message, warning = result.Warning }) + Environment.NewLine, Encoding.UTF8);
    }
}
