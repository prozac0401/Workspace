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
            throw new StateException("recovery_pending", "이전 작업이 중단되었습니다. 상태 아이콘 복구를 실행해 주세요.");
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
                throw new StateException("state_missing", "저장된 상태가 없습니다. 먼저 상태를 지정해 주세요.");
            if (action == "reset" && metadata is null)
                result = new(true, action, target, null, null, "초기화할 상태가 없습니다.");
            else
            {
                var desktop = SafeFiles.Read(Path.Combine(target, DesktopFile));
                var portable = SafeFiles.Read(Path.Combine(target, PortableFile));
                var document = IniDocument.Read(desktop.Data);
                bool folderReadOnly = File.GetAttributes(target).HasFlag(FileAttributes.ReadOnly);
                var backup = metadata?.Backup ?? new Backup(desktop, folderReadOnly, [], null);
                var changes = new List<Change>(); string? warning = null; bool afterReadOnly;
                if (action == "reset")
                {
                    Snapshot restored;
                    if (desktop.Data is not null && desktop.Data.AsSpan().SequenceEqual(backup.ManagedDesktop)) restored = backup.Desktop;
                    else if (desktop.Data is null) { restored = desktop; warning = "desktop.ini가 외부에서 삭제되어 그대로 보존했습니다."; }
                    else
                    {
                        var owned = IniDocument.Read(backup.ManagedDesktop);
                        var original = IniDocument.Read(backup.Desktop.Data);
                        foreach (string key in IconKeys)
                        {
                            if (document.Get(".ShellClassInfo", key) == owned.Get(".ShellClassInfo", key))
                                document.Set(".ShellClassInfo", key, original.Get(".ShellClassInfo", key));
                            else warning = "외부에서 변경한 아이콘 설정은 보존했습니다.";
                        }
                        // External edits keep their file attributes and folder customization bit.
                        restored = desktop with { Data = document.Bytes() };
                    }
                    changes.Add(new(DesktopFile, desktop, restored));
                    if (backup.PortableHash is not null && portable.Data is not null)
                    {
                        EnsurePortableOwned(portable, backup.PortableHash);
                        changes.Add(new(PortableFile, portable, Snapshot.Missing));
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
                        throw new StateException("icon_missing", "아이콘 파일이 없거나 손상되었습니다. 설치 프로그램의 복구 기능을 실행해 주세요.");
                    if (iconPath.Contains('\r') || iconPath.Contains('\n') || iconPath.Contains('"'))
                        throw new StateException("invalid_icon_path", "아이콘 경로를 사용할 수 없습니다.");
                    if (metadata is not null && desktop.Data is not null)
                    {
                        var managed = IniDocument.Read(backup.ManagedDesktop);
                        foreach (var key in IconKeys)
                            if (document.Get(".ShellClassInfo", key) != managed.Get(".ShellClassInfo", key))
                                throw new StateException("icon_conflict", "다른 프로그램이 폴더 아이콘을 변경했습니다. 상태 초기화 후 다시 지정해 주세요.");
                    }
                    string? portableHash = backup.PortableHash;
                    if (mode == IconMode.Portable)
                    {
                        if (portable.Data is not null) EnsurePortableOwned(portable, portableHash);
                        changes.Add(new(PortableFile, portable, new(icon.Data, HiddenSystem)));
                        portableHash = Hash(icon.Data);
                    }
                    else if (portableHash is not null)
                    {
                        if (portable.Data is not null)
                        { EnsurePortableOwned(portable, portableHash); changes.Add(new(PortableFile, portable, Snapshot.Missing)); }
                        portableHash = null;
                    }
                    document.Set(".ShellClassInfo", "IconResource", mode == IconMode.Portable ? ".folderstate.ico,0" : $"\"{iconPath}\",0");
                    document.Set(".ShellClassInfo", "IconFile", null);
                    document.Set(".ShellClassInfo", "IconIndex", null);
                    byte[] managedDesktop = document.Bytes();
                    backup = backup with { ManagedDesktop = managedDesktop, PortableHash = portableHash };
                    metadata = new(1, "FolderState", status.Value.Value(), mode.Value.ToString().ToLowerInvariant(),
                        action == "repair" ? metadata!.Updated : DateTimeOffset.Now, backup);
                    var encodedState = WriteMetadata(metadata);
                    if (encodedState.Length > SafeFiles.MaxBytes) throw new StateException("metadata_too_large", "기존 폴더 설정이 너무 커서 안전한 복구 정보를 저장할 수 없습니다.");
                    changes.Add(new(DesktopFile, desktop, new(managedDesktop, desktop.Attributes | HiddenSystem)));
                    changes.Add(new(StateFile, state, new(encodedState, state.Attributes | HiddenSystem)));
                    afterReadOnly = true;
                }
                Commit(target, new(1, "FolderState", folderReadOnly, afterReadOnly, changes.ToArray()));
                ShellRefresh.Notify(target);
                result = new(true, action, target, previous, status?.Value(), action switch
                { "reset" => "폴더 상태를 초기화했습니다.", "repair" => "저장된 상태의 아이콘을 복구했습니다.", _ => $"{status!.Value.Label()} 상태로 변경했습니다." }, Warning: warning);
            }
        }
        catch (Exception ex) when (ex is not OutOfMemoryException)
        {
            var (code, message) = Describe(ex);
            result = new(false, action, target, previous, status?.Value(), message, code);
        }
        try { if (logDirectory is not null) WriteLog(logDirectory, result); }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException or StateException)
        { result = result with { Warning = string.Join(" ", new[] { result.Warning, "로컬 로그를 기록하지 못했습니다." }.Where(s => s is not null)) }; }
        return result;
    }
    private void Commit(string target, Transaction transaction)
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
            SetReadOnly(target, transaction.AfterReadOnly);
            TransactionCheckpoint?.Invoke("attributes");
            File.Delete(journal);
        }
        catch (Exception operationError)
        {
            try { Recover(target); }
            catch (Exception recoveryError)
            { throw new StateException("recovery_failed", $"변경을 완료하지 못해 복원 정보를 보존했습니다. 잠금·권한을 확인한 후 상태 아이콘 복구를 다시 실행해 주세요. ({operationError.GetType().Name}/{recoveryError.GetType().Name})"); }
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
            if (transaction.Version != 1 || transaction.Owner != "FolderState" || transaction.Changes is null || transaction.Changes.Length is < 1 or > 3 ||
                transaction.Changes.Select(c => c.Name).Distinct(StringComparer.OrdinalIgnoreCase).Count() != transaction.Changes.Length ||
                transaction.Changes.Any(c => c.Name is not (StateFile or DesktopFile or PortableFile) || !ValidSnapshot(c.Before) || !ValidSnapshot(c.After)))
                throw new JsonException();
        }
        catch (Exception ex) when (ex is JsonException or NullReferenceException)
        { throw new StateException("invalid_journal", "중단된 작업의 복원 정보가 손상되었습니다. 메타데이터를 보존하고 지원을 요청해 주세요."); }
        var current = transaction.Changes.Select(c => SafeFiles.Read(Path.Combine(target, c.Name))).ToArray();
        for (int i = 0; i < current.Length; i++)
            if (!SafeFiles.SameData(current[i], transaction.Changes[i].Before) && !SafeFiles.SameData(current[i], transaction.Changes[i].After))
                throw new StateException("recovery_conflict", "중단 후 다른 프로그램이 설정을 변경했습니다. 복원 정보를 보존했습니다.");
        for (int i = transaction.Changes.Length - 1; i >= 0; i--)
            SafeFiles.Write(Path.Combine(target, transaction.Changes[i].Name), current[i], transaction.Changes[i].Before);
        SetReadOnly(target, transaction.BeforeReadOnly); File.Delete(journal);
    }
    private static bool ValidSnapshot(Snapshot? s) => s is not null && (s.Data?.Length ?? 0) <= SafeFiles.MaxBytes &&
        (s.Attributes & (FileAttributes.Directory | FileAttributes.ReparsePoint)) == 0;
    private static void SetReadOnly(string folder, bool enabled)
    { var attributes = File.GetAttributes(folder); File.SetAttributes(folder, enabled ? attributes | FileAttributes.ReadOnly : attributes & ~FileAttributes.ReadOnly); }
    private static string Hash(byte[] bytes) => Convert.ToHexString(SHA256.HashData(bytes));
    private static void EnsurePortableOwned(Snapshot portable, string? hash)
    {
        if (hash is null || portable.Data is null || Hash(portable.Data) != hash)
            throw new StateException("portable_conflict", "기존 .folderstate.ico가 본 도구의 아이콘과 다릅니다. 해당 파일을 보존하고 작업을 중단했습니다.");
    }
    private static IconMode ParseMode(string value) => value switch
    { "local" => IconMode.Local, "portable" => IconMode.Portable, _ => throw new StateException("invalid_metadata", "저장된 아이콘 모드를 읽을 수 없습니다.") };
    private static Metadata? ReadMetadata(Snapshot snapshot)
    {
        if (snapshot.Data is null) return null;
        try
        {
            var ini = IniDocument.Read(snapshot.Data);
            if (ini.Get("FolderState", "Version") != "1" || ini.Get("FolderState", "Owner") != "FolderState") throw new FormatException();
            var status = ini.Get("FolderState", "Status") ?? throw new FormatException(); _ = StateNames.Parse(status);
            var mode = ini.Get("FolderState", "Mode") ?? throw new FormatException(); _ = ParseMode(mode);
            var updated = DateTimeOffset.ParseExact(ini.Get("FolderState", "Updated")!, "O", System.Globalization.CultureInfo.InvariantCulture);
            var backup = JsonSerializer.Deserialize<Backup>(Convert.FromBase64String(ini.Get("FolderStateBackup", "Data")!), StateNames.Json) ?? throw new FormatException();
            if (!ValidSnapshot(backup.Desktop) || backup.ManagedDesktop is null || backup.ManagedDesktop.Length > SafeFiles.MaxBytes || backup.ManagedDesktop.Length == 0) throw new FormatException();
            _ = IniDocument.Read(backup.Desktop.Data); _ = IniDocument.Read(backup.ManagedDesktop);
            return new(1, "FolderState", status, mode, updated, backup);
        }
        catch (Exception ex) when (ex is FormatException or JsonException or ArgumentException or StateException)
        { throw new StateException("invalid_metadata", "상태 파일이 손상되었거나 지원하지 않는 형식입니다. 원본을 보존하고 작업을 중단했습니다."); }
    }
    private static byte[] WriteMetadata(Metadata data) => Encoding.UTF8.GetBytes(
        $"[FolderState]\r\nVersion=1\r\nOwner=FolderState\r\nStatus={data.Status}\r\nUpdated={data.Updated:O}\r\nMode={data.Mode}\r\n\r\n[FolderStateBackup]\r\nData={Convert.ToBase64String(JsonSerializer.SerializeToUtf8Bytes(data.Backup, StateNames.Json))}\r\n");
    private static IDisposable Acquire(string target)
    {
        var mutex = new Mutex(false, (OperatingSystem.IsWindows() ? @"Local\" : "") + "FolderState-" + Hash(Encoding.UTF8.GetBytes(target.ToUpperInvariant())));
        bool acquired;
        try { acquired = mutex.WaitOne(TimeSpan.FromSeconds(8)); }
        catch (AbandonedMutexException) { acquired = true; }
        if (!acquired) { mutex.Dispose(); throw new StateException("busy", "이 폴더의 다른 상태 작업이 진행 중입니다. 잠시 후 다시 시도해 주세요."); }
        return new MutexLease(mutex);
    }
    private sealed class MutexLease(Mutex mutex) : IDisposable
    { public void Dispose() { mutex.ReleaseMutex(); mutex.Dispose(); } }
    public static (string Code, string Message) Describe(Exception error) => error switch
    {
        StateException e => (e.Code, e.Message),
        UnauthorizedAccessException => ("access_denied", "폴더에 쓰기 권한이 없거나 보안 정책에 의해 차단되었습니다."),
        PathTooLongException => ("path_too_long", "경로가 너무 깁니다. Windows 긴 경로 설정과 저장소를 확인해 주세요."),
        IOException => ("io_error", "파일이 사용 중이거나 저장소에 접근할 수 없습니다. 연결·잠금·남은 공간을 확인해 주세요."),
        ArgumentException => ("invalid_path", "경로 또는 인수를 확인해 주세요."),
        _ => ("unexpected_error", "작업을 완료하지 못했습니다. 로그와 저장소 상태를 확인해 주세요.")
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
