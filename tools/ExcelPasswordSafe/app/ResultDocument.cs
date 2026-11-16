using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Linq;

namespace ExcelPasswordSafe
{
    /// <summary>Checks final records before advisory progress can be shown as completion.</summary>
    public static class ResultDocument
    {
        static string Text(IDictionary<string, object> data, string key)
        {
            object value;
            return data.TryGetValue(key, out value) ? value as string : null;
        }
        static string FullPath(string path)
        {
            if (String.IsNullOrWhiteSpace(path) || path.Length < 3 || !Char.IsLetter(path[0]) || path[1] != ':' ||
                (path[2] != '\\' && path[2] != '/') || path.Substring(2).Contains(":")) return null;
            try { return Path.GetFullPath(path); }
            catch (ArgumentException) { return null; }
            catch (NotSupportedException) { return null; }
            catch (PathTooLongException) { return null; }
        }
        public static bool IsValid(Dictionary<string, object> data, bool folder, IEnumerable<string> approvedPaths)
        {
            if (data == null || approvedPaths == null) return false;
            string status = Text(data, "status"), category = Text(data, "category");
            if (String.IsNullOrWhiteSpace(category)) return false;
            var approved = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (string path in approvedPaths)
            {
                string full = FullPath(path);
                if (full == null) return false;
                approved.Add(full);
            }
            if (!folder)
            {
                if (!new[] { "Success", "Skipped", "Failed", "Cancelled" }.Contains(status) || approved.Count != 1) return false;
                string path = Text(data, "path");
                if (path == null) return false;
                // The engine can fail before Assert-LocalWorkbook assigns its
                // path. It cannot succeed, skip or cancel before that point.
                if (String.IsNullOrEmpty(path)) return status == "Failed";
                string full = FullPath(path);
                return full != null && approved.Contains(full);
            }
            if (!new[] { "Success", "PartialFailure", "Failed", "Cancelled" }.Contains(status)) return false;
            object rawItems;
            if (!data.TryGetValue("items", out rawItems)) return false;
            var items = rawItems as IList;
            if (items == null) return false;
            var completed = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (object raw in items)
            {
                var item = raw as IDictionary<string, object>;
                if (item == null) return false;
                string itemStatus = Text(item, "status"), itemCategory = Text(item, "category"), path = FullPath(Text(item, "path"));
                if (path == null || String.IsNullOrWhiteSpace(itemCategory) ||
                    !new[] { "Success", "Skipped", "Failed", "Cancelled", "NotProcessed", "NeedsInspection" }.Contains(itemStatus)) return false;
                if (status == "Success" && itemStatus != "Success" && itemStatus != "Skipped") return false;
                if (approved.Contains(path))
                {
                    if (!completed.Add(path)) return false;
                }
                // Discovery issues and batch-level cleanup records may name a
                // folder outside the approved file list; they cannot add a
                // successful or retryable file to the original approval.
                else if (itemStatus != "Failed" && itemStatus != "NeedsInspection") return false;
            }
            return completed.SetEquals(approved);
        }
    }
}
