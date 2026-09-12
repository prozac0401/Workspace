using System.Runtime.InteropServices;
using System.Text;

namespace FolderState.Core;

// Preserve comments, spelling, order and unrelated keys. Ambiguous duplicate sections/keys are rejected.
internal sealed class IniDocument
{
    private readonly List<string> lines;
    private readonly string newline;
    private IniDocument(string text)
    {
        if (text.Contains('\0')) throw new StateException("invalid_ini", "INI 파일에 잘못된 문자가 있습니다.");
        newline = text.Contains("\r\n", StringComparison.Ordinal) ? "\r\n" : "\n";
        lines = text.Replace("\r\n", "\n", StringComparison.Ordinal).Split('\n').ToList();
        var sections = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var keys = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (string line in lines)
        {
            string trimmed = line.Trim();
            if (trimmed.StartsWith('[') && trimmed.EndsWith(']'))
            {
                if (!sections.Add(trimmed)) throw new StateException("ambiguous_ini", "중복된 INI 섹션이 있어 기존 설정을 안전하게 변경할 수 없습니다.");
                keys.Clear();
            }
            else if (TryKey(line, out string key) && !keys.Add(key))
                throw new StateException("ambiguous_ini", "중복된 INI 항목이 있어 기존 설정을 안전하게 변경할 수 없습니다.");
        }
    }
    public static IniDocument Read(byte[]? bytes)
    {
        if (bytes is null) return new IniDocument("");
        string text;
        try
        {
            if (bytes.AsSpan().StartsWith(new byte[] { 255, 254 })) text = new UnicodeEncoding(false, true, true).GetString(bytes, 2, bytes.Length - 2);
            else if (bytes.AsSpan().StartsWith(new byte[] { 254, 255 })) text = new UnicodeEncoding(true, true, true).GetString(bytes, 2, bytes.Length - 2);
            else if (bytes.AsSpan().StartsWith(new byte[] { 239, 187, 191 })) text = new UTF8Encoding(false, true).GetString(bytes, 3, bytes.Length - 3);
            else
            {
                try { text = new UTF8Encoding(false, true).GetString(bytes); }
                catch (DecoderFallbackException)
                {
                    Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);
                    text = Encoding.GetEncoding(OperatingSystem.IsWindows() ? (int)GetACP() : 1252,
                        EncoderFallback.ExceptionFallback, DecoderFallback.ExceptionFallback).GetString(bytes);
                }
            }
        }
        catch (DecoderFallbackException) { throw new StateException("invalid_encoding", "INI 파일의 문자 인코딩을 읽을 수 없습니다."); }
        return new IniDocument(text);
    }
    public string? Get(string section, string key)
    {
        var (start, end) = Range(section);
        for (int i = start + 1; start >= 0 && i < end; i++)
            if (TryKey(lines[i], out var found) && found.Equals(key, StringComparison.OrdinalIgnoreCase))
                return lines[i][(lines[i].IndexOf('=') + 1)..].Trim();
        return null;
    }
    public void Set(string section, string key, string? value)
    {
        var (start, end) = Range(section);
        if (start < 0)
        {
            if (value is null) return;
            if (lines.Count > 0 && lines[^1].Length != 0) lines.Add("");
            lines.Add($"[{section}]"); lines.Add($"{key}={value}"); lines.Add(""); return;
        }
        for (int i = start + 1; i < end; i++)
        {
            if (!TryKey(lines[i], out var found) || !found.Equals(key, StringComparison.OrdinalIgnoreCase)) continue;
            if (value is null) lines.RemoveAt(i); else lines[i] = lines[i][..(lines[i].IndexOf('=') + 1)] + value;
            return;
        }
        if (value is not null) lines.Insert(start + 1, $"{key}={value}");
    }
    public byte[] Bytes()
    {
        string text = string.Join(newline, lines);
        if (!text.EndsWith(newline, StringComparison.Ordinal)) text += newline;
        return [.. Encoding.Unicode.GetPreamble(), .. Encoding.Unicode.GetBytes(text)];
    }
    private (int Start, int End) Range(string section)
    {
        int start = -1;
        for (int i = 0; i < lines.Count; i++)
        {
            var line = lines[i].Trim();
            if (!line.StartsWith('[') || !line.EndsWith(']')) continue;
            if (start >= 0) return (start, i);
            if (line.Equals($"[{section}]", StringComparison.OrdinalIgnoreCase)) start = i;
        }
        return (start, lines.Count);
    }
    private static bool TryKey(string line, out string key)
    {
        key = ""; var trimmed = line.TrimStart();
        if (trimmed.StartsWith(';') || trimmed.StartsWith('#') || trimmed.StartsWith('[')) return false;
        int at = line.IndexOf('='); if (at <= 0) return false;
        key = line[..at].Trim(); return key.Length != 0;
    }
    [DllImport("kernel32.dll")] private static extern uint GetACP();
}
