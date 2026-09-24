using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Text;

namespace VisibleCellsPaste
{
    // Reads clipboard bytes only: no extraction paths, network requests, or executable parts.
    internal sealed class BoundedZip
    {
        private sealed class Entry { internal int Offset, Packed, Size, Method, Flags; internal uint Crc; internal byte[] Name; }
        private readonly byte[] bytes;
        private readonly Dictionary<string, Entry> entries = new Dictionary<string, Entry>(StringComparer.Ordinal);
        private static readonly uint[] CrcTable = MakeCrcTable();
        internal BoundedZip(byte[] value)
        {
            bytes = value;
            Require(value != null && value.Length >= 22 && value.Length <= Limits.MaxPayloadBytes);
            int end = -1;
            for (int i = bytes.Length - 22; i >= Math.Max(0, bytes.Length - 65557); i--)
                if (U32(i) == 0x06054b50 && i + 22L + U16(i + 20) == bytes.Length) { end = i; break; }
            Require(end >= 0 && U16(end + 4) == 0 && U16(end + 6) == 0);
            int count = U16(end + 10), directory = Int(U32(end + 16)), directorySize = Int(U32(end + 12));
            Require(count > 0 && count <= 128 && U16(end + 8) == count && (long)directory + directorySize == end);
            int position = directory; long total = 0; var spans = new List<long[]>();
            for (int i = 0; i < count; i++)
            {
                Require(position >= 0 && position + 46L <= end && U32(position) == 0x02014b50);
                int flags = U16(position + 8), method = U16(position + 10), nameSize = U16(position + 28), extra = U16(position + 30), comment = U16(position + 32);
                Require((flags & ~(method == 8 ? 0x806 : 0x800)) == 0 && (method == 0 || method == 8) && U16(position + 34) == 0);
                Require(nameSize > 0 && nameSize <= 240 && position + 46L + nameSize + extra + comment <= end);
                var name = new byte[nameSize]; Buffer.BlockCopy(bytes, position + 46, name, 0, nameSize);
                string text;
                try { text = new UTF8Encoding(false, true).GetString(name); } catch (DecoderFallbackException) { throw Invalid(); }
                Require(text.IndexOf('\\') < 0 && text.IndexOf(':') < 0 && !text.StartsWith("/", StringComparison.Ordinal) && !text.EndsWith("/", StringComparison.Ordinal));
                foreach (string piece in text.Split('/')) Require(piece.Length != 0 && piece != "." && piece != "..");
                Require(!entries.ContainsKey(text));
                var entry = new Entry { Flags = flags, Method = method, Crc = U32(position + 16), Packed = Int(U32(position + 20)), Size = Int(U32(position + 24)), Offset = Int(U32(position + 42)), Name = name };
                total += entry.Size; Require(total <= Limits.MaxPayloadBytes && entry.Packed <= Limits.MaxPayloadBytes);
                int local = entry.Offset;
                Require(local >= 0 && local + 30L <= directory && U32(local) == 0x04034b50 && U16(local + 6) == flags && U16(local + 8) == method);
                Require(U32(local + 14) == entry.Crc && U32(local + 18) == entry.Packed && U32(local + 22) == entry.Size && U16(local + 26) == nameSize);
                int start = local + 30 + nameSize + U16(local + 28); Require(start + (long)entry.Packed <= directory);
                for (int n = 0; n < nameSize; n++) Require(bytes[local + 30 + n] == name[n]);
                spans.Add(new long[] { local, start + (long)entry.Packed });
                entry.Offset = start; entries.Add(text, entry); position += 46 + nameSize + extra + comment;
            }
            Require(position == end);
            spans.Sort(delegate(long[] a, long[] b) { return a[0].CompareTo(b[0]); });
            long previous = 0;
            foreach (long[] span in spans) { Require(span[0] == previous); previous = span[1]; }
            Require(previous == directory);
        }
        internal IEnumerable<string> Names { get { return entries.Keys; } }
        internal bool Contains(string name) { return entries.ContainsKey(name); }
        internal byte[] Read(string name)
        {
            Entry entry; Require(entries.TryGetValue(name, out entry));
            var result = new byte[entry.Size];
            try
            {
                using (var source = new MemoryStream(bytes, entry.Offset, entry.Packed, false))
                {
                    if (entry.Method == 0) { Require(entry.Packed == entry.Size); Buffer.BlockCopy(bytes, entry.Offset, result, 0, result.Length); }
                    else using (var inflate = new DeflateStream(source, CompressionMode.Decompress, true))
                    {
                        int count = 0, read;
                        while (count < result.Length && (read = inflate.Read(result, count, result.Length - count)) > 0) count += read;
                        Require(count == result.Length && inflate.ReadByte() == -1);
                    }
                }
            }
            catch (InvalidDataException) { throw Invalid(); }
            catch (IOException) { throw Invalid(); }
            uint crc = 0xffffffff;
            foreach (byte b in result) crc = CrcTable[(crc ^ b) & 255] ^ (crc >> 8);
            Require((crc ^ 0xffffffff) == entry.Crc); return result;
        }
        private uint U32(int p) { Require(p >= 0 && p + 4L <= bytes.Length); return BitConverter.ToUInt32(bytes, p); }
        private int U16(int p) { Require(p >= 0 && p + 2L <= bytes.Length); return BitConverter.ToUInt16(bytes, p); }
        private static int Int(uint value) { Require(value <= Limits.MaxPayloadBytes); return (int)value; }
        private static uint[] MakeCrcTable()
        {
            var result = new uint[256];
            for (uint i = 0; i < 256; i++) { uint value = i; for (int n = 0; n < 8; n++) value = (value & 1) != 0 ? 0xedb88320 ^ (value >> 1) : value >> 1; result[i] = value; }
            return result;
        }
        private static void Require(bool condition) { if (!condition) throw Invalid(); }
        private static ValidationException Invalid() { return new ValidationException("VCP-NATIVE-ZIP", "Excel 네이티브 복사 데이터의 구조 또는 크기를 확인할 수 없습니다. 변경된 셀은 없습니다."); }
    }
}
