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
        else Console.WriteLine(info is null ? "상태 미지정" : $"{info.Status.Label()} ({info.Mode}) · {info.Updated:O}");
        return 0;
    }
    var results = Commands.Run(engine, command);
    if (command.Json) Console.WriteLine(JsonSerializer.Serialize(results));
    else foreach (var result in results) Console.WriteLine($"{(result.Success ? "OK" : "ERROR")} {result.TargetPath}: {result.Message} {result.Warning}");
    return results.All(r => r.Success) ? 0 : 1;
}
catch (Exception ex)
{
    var (code, message) = FolderStateEngine.Describe(ex);
    if (args.Contains("--json")) Console.WriteLine(JsonSerializer.Serialize(new { success = false, error = code, message }));
    else Console.Error.WriteLine(message);
    return code is "usage" or "invalid_status" ? 2 : 1;
}
