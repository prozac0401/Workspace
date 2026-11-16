using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Linq;
using System.Windows.Media;

namespace ExcelPasswordSafe
{
    public enum WizardStep { Target, Operation, Input, Progress, Result }

    public sealed class WorkItem : INotifyPropertyChanged
    {
        public string Path { get; set; }
        public string Name { get; set; }
        string state = "Pending", category = "", attempts = "0";
        public string State { get { return state; } set { state = value; Changed(); } }
        public string Category { get { return category; } set { category = value; Changed(); } }
        public string Attempts { get { return attempts; } set { attempts = value; Changed(); } }
        public string Label
        {
            get
            {
                switch (state)
                {
                    case "Success": return "완료";
                    case "Skipped": return "건너뜀";
                    case "Failed": return "실패";
                    case "NeedsInspection": return "확인 필요";
                    case "Cancelled": return "취소";
                    case "NotProcessed": return "미처리";
                    case "Processing": return "처리 중";
                    default: return "대기";
                }
            }
        }
        public string Detail { get { return state == "Pending" ? "" : state == "Processing" ? "저장 결과를 확인하고 있습니다." : BatchWorkflow.Reason(category); } }
        public string Caption { get { return Label + (attempts == "0" ? "" : " · " + attempts + "회 시도"); } }
        public string FullDescription { get { return Path + "\n" + Caption + (Detail.Length == 0 ? "" : "\n" + Detail); } }
        public Brush Color { get { return state == "Failed" || state == "NeedsInspection" ? Brushes.Firebrick : state == "Success" ? Brushes.RoyalBlue : Brushes.SlateGray; } }
        public event PropertyChangedEventHandler PropertyChanged;
        void Changed() { var callback = PropertyChanged; if (callback != null) callback(this, new PropertyChangedEventArgs("")); }
    }

    public static class WizardRules
    {
        public const string DisplayVersion = "2";
        public static bool NeedsInspection(string category)
        {
            return new[] { "CommitUncertain", "SourceChanged", "WorkerTimeout", "WorkerInterrupted", "WorkerCrashed",
                "ExcelStillRunning", "ExcelOwnershipOrExistingProcess", "MissingChildResult", "InvalidChildResult",
                "TemporaryCleanupIncomplete", "BackupChanged", "TempChanged", "SnapshotChanged", "MissingResult" }.Contains(category);
        }
        public static bool Retryable(string category)
        {
            return new[] { "OpenFailedPossiblePasswordOrCorruption", "FileInUse", "ReadOnlyAttribute", "AccessDenied",
                "ExistingExcel", "AnotherOperationRunning", "ComServerError", "ValidationFailed", "FileNotFound",
                "PreflightFailed", "BackupFailed", "ComCleanupFailed", "SaveAsFailed", "ComStartFailed", "CommitFailed",
                "ComRegistrationOrLibrary" }.Contains(category);
        }
        public static string[] RetryPaths(IEnumerable<WorkItem> items, IEnumerable<string> approvedPaths)
        {
            var list = items.ToArray();
            if (list.Any(item => item.State == "NeedsInspection" || NeedsInspection(item.Category))) return new string[0];
            var approved = new HashSet<string>(approvedPaths, StringComparer.OrdinalIgnoreCase);
            return list.Where(item => approved.Contains(item.Path) &&
                (item.State == "Failed" || item.State == "NotProcessed") && Retryable(item.Category))
                .Select(item => item.Path).Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
        }
    }
}
