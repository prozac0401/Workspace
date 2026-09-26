using System;
using System.IO;
using System.Runtime.InteropServices;

namespace ExcelSelectionExport
{
    // Owns only a freshly created, hidden output application and its temporary
    // template. The engine owns every workbook/range reference and must close
    // and release those references before CloseApplication.
    internal sealed class OutputWorkspace : IDisposable
    {
        object application;
        readonly Action<object> releaseObject;
        readonly Action<string> deleteFile;
        readonly string temporaryRoot;
        string temporaryDirectory;
        string templatePath;

        internal OutputWorkspace(object sourceApplication)
            : this(sourceApplication, CreateApplication, Release,
                Path.Combine(Path.GetTempPath(), "Workspace", "ExcelSelectionExport"), File.Delete)
        {
        }

        // A pure managed seam: lifecycle tests supply fake applications and never
        // activate Excel, inspect another process, or change user documents.
        internal OutputWorkspace(object sourceApplication, Func<object> createApplication,
            Action<object> release, string tempRoot, Action<string> removeFile)
        {
            if (sourceApplication == null) throw new ArgumentNullException("sourceApplication");
            if (createApplication == null) throw new ArgumentNullException("createApplication");
            if (release == null) throw new ArgumentNullException("release");
            if (removeFile == null) throw new ArgumentNullException("removeFile");
            if (String.IsNullOrEmpty(tempRoot)) throw new ArgumentException("A temporary root is required.", "tempRoot");
            releaseObject = release;
            deleteFile = removeFile;
            temporaryRoot = Path.GetFullPath(tempRoot);

            object created = createApplication();
            if (created == null) throw new InvalidOperationException("출력용 Excel을 시작하지 못했습니다.");
            if (Same(sourceApplication, created))
                throw new InvalidOperationException("원본과 독립된 출력용 Excel을 확보하지 못해 내보내기를 중단했습니다.");
            application = created;
            try
            {
                // Refuse to hide or alter an unexpected pre-existing document.
                RequireEmptyApplication();
                dynamic worker = application;
                worker.Visible = false;
                worker.EnableEvents = false;
                worker.DisplayAlerts = false;
                worker.Interactive = false;
                worker.ScreenUpdating = false;
            }
            catch (Exception startupError)
            {
                try { CloseApplication(); }
                catch (Exception cleanupError)
                {
                    throw new InvalidOperationException("출력용 Excel 준비에 실패했고 안전한 정리도 완료하지 못했습니다. 원본 Excel은 종료하지 않았습니다.",
                        new AggregateException(startupError, cleanupError));
                }
                throw;
            }
        }

        internal object Application
        {
            get
            {
                if (application == null) throw new ObjectDisposedException("OutputWorkspace");
                return application;
            }
        }

        internal string SaveTemplate(object workbook)
        {
            if (workbook == null) throw new ArgumentNullException("workbook");
            object worker = Application;
            object workbookApplication = null;
            try
            {
                workbookApplication = ((dynamic)workbook).Application;
                if (!Same(worker, workbookApplication))
                    throw new InvalidOperationException("출력용 Excel에서 만든 통합문서만 임시 저장할 수 있습니다.");
            }
            finally { releaseObject(workbookApplication); }
            if (temporaryDirectory != null)
                throw new InvalidOperationException("이미 생성했거나 아직 정리하지 못한 임시 결과가 있습니다.");

            try
            {
                Directory.CreateDirectory(temporaryRoot);
                // A random, per-operation directory keeps the fixed display name
                // independent of the user's files. No existing file is overwritten.
                string candidate;
                do { candidate = Path.Combine(temporaryRoot, Guid.NewGuid().ToString("N")); }
                while (Directory.Exists(candidate) || File.Exists(candidate));
                Directory.CreateDirectory(candidate);
                temporaryDirectory = candidate;
                templatePath = Path.Combine(candidate, "Selection.xlsx");
                if (File.Exists(templatePath)) throw new IOException("The temporary output path already exists.");
                // xlsx; no password, read-only recommendation, backup, or MRU entry.
                ((dynamic)workbook).SaveAs(templatePath, 51, Type.Missing, Type.Missing,
                    false, false, 1, Type.Missing, false);
                if (!File.Exists(templatePath)) throw new IOException("Excel did not create the temporary template.");
                return templatePath;
            }
            catch (Exception saveError)
            {
                try { DeleteTemporaryFiles(); }
                catch (Exception cleanupError)
                {
                    throw new InvalidOperationException("임시 결과 저장에 실패했고 정리도 완료하지 못했습니다. 작업 정리 시 다시 시도합니다.",
                        new AggregateException(saveError, cleanupError));
                }
                throw;
            }
        }

        internal void CloseApplication()
        {
            if (application == null) return;
            RequireEmptyApplication();
            object retiring = application;
            ((dynamic)retiring).Quit();
            application = null;
            releaseObject(retiring);
        }

        void RequireEmptyApplication()
        {
            object books = null;
            try
            {
                books = ((dynamic)application).Workbooks;
                if (Convert.ToInt32(((dynamic)books).Count) != 0)
                    throw new InvalidOperationException("출력용 Excel에 아직 통합문서가 남아 있어 종료하지 않았습니다. 해당 문서를 안전하게 정리한 뒤 다시 시도해 주세요.");
            }
            finally { releaseObject(books); }
        }

        void DeleteTemporaryFiles()
        {
            if (templatePath != null)
            {
                // Keep the exact path after any failure so Dispose can retry.
                deleteFile(templatePath);
                templatePath = null;
            }
            if (temporaryDirectory != null)
            {
                // Never recurse: an unexpected file is preserved and reported.
                if (Directory.Exists(temporaryDirectory)) Directory.Delete(temporaryDirectory, false);
                temporaryDirectory = null;
            }
        }

        public void Dispose()
        {
            Exception failure = null;
            try { CloseApplication(); }
            catch (Exception error) { failure = error; }
            try { DeleteTemporaryFiles(); }
            catch (Exception error)
            {
                failure = failure == null ? error : new AggregateException(failure, error);
            }
            if (failure != null)
                throw new InvalidOperationException("출력용 Excel 또는 임시 파일의 안전한 정리가 완료되지 않았습니다. 원본은 유지했으며 정리를 다시 시도할 수 있습니다.", failure);
        }

        static object CreateApplication()
        {
            Type type = Type.GetTypeFromProgID("Excel.Application");
            if (type == null) throw new InvalidOperationException("출력용 Excel 프로그램을 찾지 못했습니다.");
            return Activator.CreateInstance(type);
        }

        static bool Same(object left, object right)
        {
            if (left == null || right == null) return false;
            if (Object.ReferenceEquals(left, right)) return true;
            if (!Marshal.IsComObject(left) || !Marshal.IsComObject(right)) return false;
            IntPtr first = IntPtr.Zero, second = IntPtr.Zero;
            try
            {
                first = Marshal.GetIUnknownForObject(left);
                second = Marshal.GetIUnknownForObject(right);
                return first == second;
            }
            finally
            {
                if (second != IntPtr.Zero) Marshal.Release(second);
                if (first != IntPtr.Zero) Marshal.Release(first);
            }
        }

        static void Release(object value)
        {
            if (value != null && Marshal.IsComObject(value))
                try { Marshal.ReleaseComObject(value); }
                catch (InvalidComObjectException) { }
        }
    }
}
