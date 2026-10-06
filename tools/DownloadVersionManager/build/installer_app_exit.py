"""Request the installed watcher's existing tray Exit command, never force exit."""
import ctypes as C
from ctypes import wintypes as W
from installer_evidence import TrialBlocked, TrialIncomplete

WINDOW_CLASS = 'Workspace.DvmWatcher'


def request_installed_app_exit(user32, window, process_id):
    """Reject unrelated windows before requesting the product's normal shutdown."""
    owner = W.DWORD()
    class_name = C.create_unicode_buffer(256)
    user32.GetWindowThreadProcessId(window, C.byref(owner))
    if (owner.value != process_id or
            not user32.GetClassNameW(window, class_name, len(class_name)) or
            class_name.value != WINDOW_CLASS):
        raise TrialBlocked('BLOCKED: installed application main window ownership changed; no exit sent')
    if not user32.PostMessageW(window, 0x0111, 106, 0):  # WM_COMMAND, existing TrayExit.
        raise TrialIncomplete('Normal tray Exit command could not be posted; preserve state and stop')
