using System.Text.Json;

namespace FolderState.Core;

public enum WorkStatus { Todo, Doing, Done, Issue }
public enum IconMode { Local, Portable }
public sealed record StateInfo(WorkStatus Status, IconMode Mode, DateTimeOffset Updated);
public sealed record OperationResult(bool Success, string Action, string TargetPath, string? PreviousStatus,
    string? NewStatus, string Message, string? ErrorCode = null, string? Warning = null);
public sealed class StateException(string code, string message) : Exception(message)
{ public string Code { get; } = code; }

internal sealed record Snapshot(byte[]? Data, FileAttributes Attributes)
{
    public static readonly Snapshot Missing = new(null, 0);
    [System.Text.Json.Serialization.JsonExtensionData]
    public Dictionary<string, JsonElement>? Extensions { get; init; }
}
internal sealed record Backup(Snapshot Desktop, bool FolderReadOnly, byte[] ManagedDesktop, string? PortableHash,
    string? PortableName = null)
{
    [System.Text.Json.Serialization.JsonExtensionData]
    public Dictionary<string, JsonElement>? Extensions { get; init; }
}
internal sealed record Metadata(int Version, string Owner, string Status, string Mode, DateTimeOffset Updated, Backup Backup);
internal sealed record Change(string Name, Snapshot Before, Snapshot After);
internal sealed record Transaction(int Version, string Owner, bool BeforeReadOnly, bool AfterReadOnly, Change[] Changes);

public static class StateNames
{
    public static string Value(this WorkStatus state) => state.ToString().ToLowerInvariant();
    public static string Label(this WorkStatus state) => state switch
    { WorkStatus.Todo => "미착수", WorkStatus.Doing => "진행 중", WorkStatus.Done => "완료", _ => "이슈" };
    public static WorkStatus Parse(string value) => value switch
    { "todo" => WorkStatus.Todo, "doing" => WorkStatus.Doing, "done" => WorkStatus.Done, "issue" => WorkStatus.Issue,
        _ => throw new StateException("invalid_status", "상태는 todo, doing, done, issue 중 하나여야 합니다.") };
    internal static readonly JsonSerializerOptions Json = new() { WriteIndented = false };
}
