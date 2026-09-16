using System.Text;
using System.Text.Json;
using FolderState.Core;

Console.OutputEncoding = Encoding.UTF8;
if (args.Length == 0 || args[0] is "--help" or "-h") { Console.WriteLine(Commands.Usage); return 0; }
if (args[0] == "--version") { Console.WriteLine(typeof(Commands).Assembly.GetName().Version?.ToString(3)); return 0; }
try
{
    if (!OperatingSystem.IsWindows()) throw new StateException("platform", "Windows에서 실행해 주세요.");
    var command = Commands.Parse(args); var engine = Commands.CreateEngine();
    if (command.Action == "status")
    {
        var info = engine.ReadState(command.Folders[0]);
        if (command.Json) Console.WriteLine(JsonSerializer.Serialize(new { success = true, target_path = command.Folders[0], status = info?.Status.Value(), mode = info?.Mode.ToString().ToLowerInvariant(), updated = info?.Updated }));
        else Console.WriteLine(info is null ? "아직 상태를 표시하지 않은 폴더입니다." : $"현재 상태: {info.Status.Label()}\n아이콘 저장 위치: {(info.Mode == IconMode.Local ? "이 PC" : "선택한 폴더 안")}\n마지막으로 바꾼 때: {info.Updated:O}");
        return 0;
    }
    var results = Commands.Run(engine, command);
    if (command.Json) Console.WriteLine(JsonSerializer.Serialize(results));
    else foreach (var result in results) Console.WriteLine($"{(result.Success ? "성공" : "실패")} · {result.TargetPath}\n{result.Message}{(result.Warning is null ? "" : "\n안내: " + result.Warning)}");
    return results.All(r => r.Success) ? 0 : 1;
}
catch (Exception ex)
{
    var (code, message) = FolderStateEngine.Describe(ex);
    if (args.Contains("--json")) Console.WriteLine(JsonSerializer.Serialize(new { success = false, error = code, message }));
    else Console.Error.WriteLine(message);
    return code is "usage" or "invalid_status" ? 2 : 1;
}
