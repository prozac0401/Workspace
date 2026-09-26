using ImageCopySave.Helper;
using System.Text.Json;
using System.Text;

namespace ImageCopySave.Tests;

internal static class HelperContractTests
{
    public static void Register(Action<string, Action> test)
    {
        test("helper shell invoke protocol preserves context", () =>
        {
            string path = @"C:\그림 폴더 (시험)\이미지.png";
            Check.That(ShellRequest.TryParse(["--shell", "copy", path, "4294967295", "12345"], out var request));
            Check.That(request == new ShellRequest("copy", path, uint.MaxValue, 12345));
            Check.That(ShellRequest.TryParse(["--shell", "save", @"C:\", "0", "0"], out _));
        });
        test("helper shell invoke rejects malformed numeric and path arguments", () =>
        {
            string[] valid = ["--shell", "save", @"C:\folder", "17", "123"];
            foreach (string value in new[] { "-1", "+17", " 17", "17 ", "4294967296", "1e3", "" })
            {
                string[] args = (string[])valid.Clone(); args[3] = value;
                Check.That(!ShellRequest.TryParse(args, out _), "Accepted malformed sequence.");
            }
            foreach (string value in new[] { "-1", "0x123", "9223372036854775808", "" })
            {
                string[] args = (string[])valid.Clone(); args[4] = value;
                Check.That(!ShellRequest.TryParse(args, out _), "Accepted malformed HWND.");
            }
            foreach (string value in new[] { "relative.png", @"C:relative.png", "C:\\bad\nname", "" })
            {
                string[] args = (string[])valid.Clone(); args[2] = value;
                Check.That(!ShellRequest.TryParse(args, out _), "Accepted missing/ambiguous output context.");
            }
            Check.That(!ShellRequest.TryParse(valid[..^1], out _));
            Check.That(!ShellRequest.TryParse([.. valid, "extra"], out _));
        });
        test("helper feedback reports saved path and uncertain commit honestly", () =>
        {
            var request = new ShellRequest("save", @"C:\folder", 0, 0);
            string path = @"C:\folder\그림.png";
            Check.That(ShellFeedback.ResultMessage(request, new WorkerResult(0, path + "\r\n", "")).Contains(path, StringComparison.Ordinal));
            string message = ShellFeedback.ResultMessage(request, new WorkerResult(1, "",
                "{\"error\":\"ClipboardOperationException\",\"clipboardMayHaveChanged\":true,\"message\":\"failure\"}"));
            Check.That(message.Contains("바뀌었을 수", StringComparison.Ordinal));
            message = ShellFeedback.ResultMessage(request, new WorkerResult(1, "", "{\"error\":\"ClipboardChangedException\"}"));
            Check.That(message.Contains("새 복사 내용은 그대로", StringComparison.Ordinal));
        });
        test("helper feedback gives committed action precedence over output failure", () =>
        {
            foreach (string operation in new[] { "copy", "save" })
            {
                var request = new ShellRequest(operation, @"C:\private-source-path", 0, 0);
                string diagnostic = JsonSerializer.Serialize(new { error = "IOException", stage = "output", operationCompleted = true,
                    clipboardMayHaveChanged = operation == "copy", fileMayHaveBeenCreated = operation == "save" });
                string message = ShellFeedback.ResultMessage(request, new WorkerResult(1, "", diagnostic));
                Check.That(message.Contains("작업은 완료", StringComparison.Ordinal) && !message.Contains("완료하지 못", StringComparison.Ordinal),
                    "A post-commit transport failure was reported as an uncommitted operation.");
            }
        });
        test("helper feedback keeps supervision failure uncertain and cancellation distinct", () =>
        {
            var request = new ShellRequest("copy", @"C:\private-source-path", 0, 0);
            string diagnostic = JsonSerializer.Serialize(new { error = "TimeoutException", stage = "supervision",
                operationCompleted = (bool?)null, clipboardMayHaveChanged = true, fileMayHaveBeenCreated = true });
            string message = ShellFeedback.ResultMessage(request, new WorkerResult(1, "", diagnostic));
            Check.That(message.Contains("불확실", StringComparison.Ordinal) && message.Contains("파일 저장", StringComparison.Ordinal));
            message = ShellFeedback.ResultMessage(request, new WorkerResult(3, "", "커밋 전에 작업을 취소했습니다."));
            Check.That(message == "커밋 전에 작업을 취소했습니다.");
            const string forced = "작업을 강제 중단했습니다. 파일 저장 완료 여부와 클립보드 보존 여부는 불확실합니다. 임시 파일이 남을 수 있습니다.";
            Check.That(ShellFeedback.ResultMessage(request, new WorkerResult(3, "", forced)) == forced);
        });
        test("helper feedback distinguishes actionable precommit failures without paths", () =>
        {
            var request = new ShellRequest("save", @"C:\private-source-path", 0, 0);
            foreach (var failure in new[]
            {
                ("InvalidDataException", (int?)null, 0, "형식·크기"),
                ("IOException", (int?)5, 0, "권한"),
                ("IOException", (int?)null, unchecked((int)0x80070005), "권한"),
                ("Win32Exception", (int?)112, 0, "저장 공간"),
                ("IOException", (int?)null, unchecked((int)0x80070027), "저장 공간"),
                ("IOException", (int?)3, 0, "폴더를 찾지"),
                ("OutOfMemoryException", (int?)null, 0, "메모리"),
                ("ClipboardOperationException", (int?)5, 0, "그림을 읽지")
            })
            {
                string diagnostic = JsonSerializer.Serialize(new { error = failure.Item1, nativeCode = failure.Item2,
                    code = failure.Item3, stage = "save", operationCompleted = false, clipboardMayHaveChanged = false });
                string message = ShellFeedback.ResultMessage(request, new WorkerResult(1, "", diagnostic));
                Check.That(message.Contains(failure.Item4, StringComparison.Ordinal), "Specific recoverable error was not explained.");
                Check.That(!message.Contains(request.Target, StringComparison.Ordinal), "Failure feedback disclosed the source path.");
            }
        });
        test("helper shell feedback survives selection output channel failure", () =>
        {
            var result = new WorkerResult(0, "C:\\folder\\그림.png\r\n", "");
            foreach (bool failOnFlush in new[] { false, true })
            {
                using var broken = new FailedWriter(failOnFlush);
                var actual = ImageCopySave.Helper.Program.DeliverResult(result, true, broken, broken);
                Check.That(actual == result && actual.Output.Contains("그림.png", StringComparison.Ordinal));
                Check.Throws<IOException>(() => ImageCopySave.Helper.Program.DeliverResult(result, false, broken, TextWriter.Null));
            }
            using var output = new StringWriter();
            using var error = new StringWriter();
            Check.That(ImageCopySave.Helper.Program.DeliverResult(result, true, output, error) == result);
            Check.That(output.ToString() == result.Output && error.ToString() == "");
        });
    }

    private sealed class FailedWriter(bool failOnFlush) : TextWriter
    {
        public override Encoding Encoding => Encoding.UTF8;
        public override void Write(string? value) { if (!failOnFlush) throw new IOException("Simulated disconnected result pipe."); }
        public override void Flush() { if (failOnFlush) throw new IOException("Simulated disconnected result pipe."); }
    }
}
