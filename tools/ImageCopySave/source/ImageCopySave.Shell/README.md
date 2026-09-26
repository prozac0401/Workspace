# ImageCopySave native Shell adapter — integrated evaluation candidate

This directory implements two native C++17 `IExplorerCommand` classes. The approved
G0 target is a standalone command on a real local folder's Windows 11 background
menu, plus a command on a single supported image file. Neither class creates a
submenu, separator, registration entry or legacy fallback.

| Command | Class ID | Title |
|---|---|---|
| Save | `{9C030D44-BBFA-48B7-BD63-53470C112830}` | 복사한 그림 저장 |
| Copy | `{B481F5D0-A2B3-47D7-A139-B6C2F60B36DE}` | 그림으로 복사 |

## Build and activation contract

- Windows x64, C++17, Windows SDK headers/libraries; no ATL or CLR.
- Compile `ImageCopySave.Shell.cpp` with `/std:c++17 /EHsc /utf-8 /MT`,
  `UNICODE`, `_UNICODE`, `WIN32_LEAN_AND_MEAN` and `NOMINMAX`.
- Link as a DLL using `ImageCopySave.Shell.def`, `ole32.lib`, `shell32.lib`,
  `user32.lib` and `uuid.lib`.
- Export only `DllGetClassObject` and `DllCanUnloadNow`. There is deliberately
  no self-registration export.
- The installer must register these as apartment-threaded classes and bind Save
  only to the real folder-background context, Copy only to intended file contexts.
  Actual Windows 11 first-menu visibility and package activation remain G0 tests.
- Deploy `ImageCopySave.Helper.exe` and its published dependencies alongside
  `ImageCopySave.Shell.dll`. Invoke starts that exact executable, with
  `--shell save|copy <absolute target> <invokeSequence> <parentHwnd>`. It does not search PATH,
  start a command interpreter, elevate, wait for image processing or open an editor.
- Invoke reads its own process window-station and calling-thread desktop names
  using UOI_NAME, then explicitly supplies station\desktop in STARTUPINFO. If
  either identity cannot be obtained, launch fails without a default-desktop
  fallback. No context is switched and no borrowed handle is closed. Actual
  Explorer/package launch behavior remains NOT RUN.

## State and context contract


GetState honors Explorer's slow-evaluation contract. With `fOkToBeSlow=FALSE`,
it only checks whether the Save site is null or the Copy selection is absent,
invalid or not exactly one item. These conclusive exclusions return
`S_OK/ECS_HIDDEN`; a remaining candidate returns `E_PENDING`, with the output
initialized to `ECS_HIDDEN`. This branch does not obtain Shell items, query the
site, resolve paths, probe drive/ancestor attributes or query the clipboard.
Only `fOkToBeSlow=TRUE` performs the remaining metadata checks. The DLL caches
neither an enabled state nor an image. Actual deferred-state behavior and warm
P95/cold timing still require Explorer measurements; they are not proven by
this gate or by a fast unit test.

Save obtains `IServiceProvider` from its `IObjectWithSite` caller site, queries
`SID_SFolderView` for `IFolderView`, gets `IPersistFolder2`, then converts its
current absolute folder PIDL to an `IShellItem` and `SIGDN_FILESYSPATH`.
Missing interfaces, virtual folders and failed metadata checks return
`ECS_HIDDEN`. A selected folder, other Explorer window, active window or process
working directory is never a destination fallback.

Copy requires exactly one `IShellItem` representing a filesystem file, with
PNG/JPG/JPEG/BMP extension. Both paths require a drive-letter absolute path on a
fixed local volume. Network, SUBST/device aliases and reparse, offline or recall
attributes on the item or any ancestor are rejected. Only ancestors are inspected;
there is no descendant enumeration. Paths with more than 256 components or 32,766
characters are hidden to bound metadata work. Device/UNC prefixes, dot segments,
alternate streams and ambiguous trailing spaces/dots/separators are also rejected.
Reserved device components (including extension forms such as CON.png, COM1 and
LPT¹, plus console aliases) are rejected before filesystem calls. This ordinary
Shell-path gate is intentionally narrower than the engine's extended-namespace
handle opening, which has no separate reserved-name filter.

After Save's folder is validated, clipboard state uses format metadata only:
registered `PNG`, `CF_DIBV5`, `CF_DIB` and `CF_BITMAP`. Text, HTML, file lists,
OLE-only and vector formats cannot independently enable Save. A clipboard
sequence change during probing fails closed. No clipboard is opened, no payload
is read, and no delayed data rendering or image decoding is requested by the DLL.
A later menu opening repeats the checks; Invoke resolves paths and checks Save's
format availability again. The helper must independently revalidate before any
read/write because metadata checks are not a filesystem transaction.

## Verification and remaining work

`ShellPolicy.h` contains side-effect-free functions shared with native tests.
Tests can call the DLL exports directly without OS registration. Calling Save
GetState with no caller site cannot reach clipboard APIs. Copy state never reads
the clipboard. Clipboard-positive and real Explorer integration tests must run
only in an authorized isolated desktop/test environment.

The invocation captures the clipboard sequence before path validation and process
startup. Copy validates this baseline under its publication lock; Shell Save
validates it under its capture lock before reading data. A change before that lock
cancels the request instead of silently substituting a later image. Delayed
rendering after the lock does not invalidate a coherent captured snapshot.

The helper's task mode displays nonmodal progress/cancel/success/error feedback.
The native adapter redirects UTF-8 stdout through a bounded private pipe and
inherits only its three explicit standard handles. A background monitor reads
the result for at most 30 seconds; Invoke never waits for image work. The monitor
pins the DLL while active and retains only a marshaled interface to the original
view, not a search over Explorer windows. It accepts a successful PNG path only
when it is a direct child of the invoking folder. Selection requires the same
view HWND, matching current folder, a visible view and the foreground root window.
It never activates, navigates, renames or opens an Explorer window. Selection
failure leaves the saved file successful, with its path in the helper feedback.

If the helper cannot start, a short native nonactivating error notice is attempted.
Its failure does not change the original HRESULT. Module references and pipe/COM
resources are owned per invocation. There is no persistent service or watcher.

These are implementation contracts, not proof of actual Explorer behavior. The
native harness tests policy and COM boundaries without Invoke. First-menu
placement, positive caller-site resolution, tab changes, no-focus behavior,
launch failure feedback and installation still require the manual checks in
[PC verification](../../../../docs/tools/image-copy-save/local-verification.md).
No M0/M2/M3 acceptance result is inferred from a successful native compile.


Reference API contracts:
[GetState](https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/nf-shobjidl_core-iexplorercommand-getstate),
[GetFlags](https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/nf-shobjidl_core-iexplorercommand-getflags),
[IFolderView::GetFolder](https://learn.microsoft.com/en-us/windows/win32/api/shobjidl_core/nf-shobjidl_core-ifolderview-getfolder),
[Windows path naming](https://learn.microsoft.com/en-us/windows/win32/fileio/naming-a-file),
[STARTUPINFOW](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/ns-processthreadsapi-startupinfow),
[GetUserObjectInformationW](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getuserobjectinformationw).
