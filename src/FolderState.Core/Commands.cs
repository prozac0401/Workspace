namespace FolderState.Core;

public sealed record Command(string Action, WorkStatus? Status, IconMode? Mode, string[] Folders, bool Json);
public static class Commands
{
    public const string Usage = "FolderState.Cli set <todo|doing|done|issue> <folder> [more folders] [--mode local|portable] [--json]\nFolderState.Cli reset <folder> [more folders] [--json]\nFolderState.Cli repair <folder> [more folders] [--json]\nFolderState.Cli status <folder> [--json]";
    public static Command Parse(string[] args)
    {
        if (args.Length < 2) throw new StateException("usage", Usage);
        string action = args[0].ToLowerInvariant();
        if (action is not ("set" or "reset" or "repair" or "status")) throw new StateException("usage", Usage);
        int i = 1; WorkStatus? status = null; IconMode? mode = null; bool json = false;
        if (action == "set") { status = StateNames.Parse(args[i++]); }
        var folders = new List<string>(); bool positional = false;
        while (i < args.Length)
        {
            string item = args[i++];
            if (!positional && item == "--") { positional = true; continue; }
            if (!positional && item == "--json") { json = true; continue; }
            if (!positional && item == "--mode")
            {
                if (action != "set" || mode is not null || i >= args.Length) throw new StateException("usage", Usage);
                mode = args[i++] switch { "local" => IconMode.Local, "portable" => IconMode.Portable, _ => throw new StateException("usage", Usage) }; continue;
            }
            if (!positional && item.StartsWith("--", StringComparison.Ordinal)) throw new StateException("usage", Usage);
            folders.Add(item);
        }
        if (folders.Count == 0 || folders.Count > 100 || (action == "status" && folders.Count != 1)) throw new StateException("usage", Usage);
        return new(action, status, mode, folders.Distinct(StringComparer.OrdinalIgnoreCase).ToArray(), json);
    }
    public static OperationResult[] Run(FolderStateEngine engine, Command command) => command.Folders.Select(folder => command.Action switch
    { "set" => engine.Set(folder, command.Status!.Value, command.Mode), "reset" => engine.Reset(folder), "repair" => engine.Repair(folder),
        _ => throw new StateException("usage", Usage) }).ToArray();
    public static FolderStateEngine CreateEngine() => new(Path.Combine(AppContext.BaseDirectory, "icons"),
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "FolderState", "logs"));
}
