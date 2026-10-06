"""Focused exit regression; no application, installer or Windows API is executed."""
import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1] / 'build'))
from installer_app_exit import WINDOW_CLASS, request_installed_app_exit
from installer_evidence import TrialBlocked, TrialIncomplete


class TrayWindow:
    def __init__(self, pid=123, class_name=WINDOW_CLASS, can_post=True):
        self.pid, self.class_name, self.can_post = pid, class_name, can_post
        self.running, self.visible, self.messages = True, True, []

    def GetWindowThreadProcessId(self, window, owner):
        owner._obj.value = self.pid
        return 1

    def GetClassNameW(self, window, name, capacity):
        name.value = self.class_name
        return len(self.class_name)

    def PostMessageW(self, window, message, command, parameter):
        self.messages.append((window, message, command, parameter))
        if not self.can_post:
            return 0
        if message == 0x0010:
            self.visible = False  # 0.2.1 WM_CLOSE keeps the watcher alive.
        elif message == 0x0111 and command == 106:
            self.running = False
        return 1


class InstalledAppExitTests(unittest.TestCase):
    def test_close_hides_but_trial_requests_normal_tray_exit(self):
        app = TrayWindow()
        app.PostMessageW(10, 0x0010, 0, 0)
        self.assertTrue(app.running)
        self.assertFalse(app.visible)
        app.messages.clear()
        request_installed_app_exit(app, 10, 123)
        self.assertFalse(app.running)
        self.assertEqual([(10, 0x0111, 106, 0)], app.messages)

    def test_other_process_receives_no_exit(self):
        app = TrayWindow(pid=456)
        with self.assertRaises(TrialBlocked):
            request_installed_app_exit(app, 10, 123)
        self.assertTrue(app.running)
        self.assertEqual([], app.messages)

    def test_other_window_class_receives_no_exit(self):
        app = TrayWindow(class_name='UnrelatedWindow')
        with self.assertRaises(TrialBlocked):
            request_installed_app_exit(app, 10, 123)
        self.assertTrue(app.running)
        self.assertEqual([], app.messages)

    def test_failed_post_is_incomplete_and_does_not_retry(self):
        app = TrayWindow(can_post=False)
        with self.assertRaises(TrialIncomplete):
            request_installed_app_exit(app, 10, 123)
        self.assertTrue(app.running)
        self.assertEqual([(10, 0x0111, 106, 0)], app.messages)


if __name__ == '__main__':
    unittest.main(verbosity=2)
