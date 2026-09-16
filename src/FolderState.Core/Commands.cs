namespace FolderState.Core;

public sealed record Command(string Action, WorkStatus? Status, IconMode? Mode, string[] Folders, bool Json);
public static class Commands
{
    public const string Usage = """
        FolderState · 폴더에 진행 상황 표시하기

        상태 바꾸기:
          FolderState.Cli set <todo|doing|done|issue> <folder> [more folders] [--mode local|portable] [--json]
        상태 표시 지우기:
          FolderState.Cli reset <folder> [more folders] [--json]
        저장된 상태의 아이콘 다시 표시하기:
          FolderState.Cli repair <folder> [more folders] [--json]
        저장된 상태 확인하기:
          FolderState.Cli status <folder> [--json]

        상태값: todo=시작 전, doing=진행 중, done=완료, issue=확인 필요
        <folder>에는 폴더의 전체 경로를 큰따옴표로 감싸서 입력하세요.
        [more folders]는 함께 처리할 폴더입니다. 최대 100개까지 직접 입력할 수 있습니다.
        --mode local: 이 PC에 설치된 아이콘 사용 / portable: 선택한 폴더 안에 아이콘 저장
        --json: 다른 프로그램에서 읽을 수 있는 형식으로 결과 출력
        대괄호로 표시된 부분은 필요할 때만 입력합니다.

        예: FolderState.Cli set doing "D:\Work\교육 준비"
        """;
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
