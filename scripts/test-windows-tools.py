#!/usr/bin/env python3
"""Check argument preservation, exit codes, and timeout process cleanup."""

import ctypes
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest


RUNNER = Path(__file__).resolve().with_name("run-command.py")


def alive(pid):
    if os.name == "nt":
        kernel = ctypes.WinDLL("kernel32", use_last_error=True)
        kernel.OpenProcess.restype = ctypes.c_void_p
        kernel.OpenProcess.argtypes = [ctypes.c_uint32, ctypes.c_int, ctypes.c_uint32]
        kernel.GetExitCodeProcess.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_uint32)]
        kernel.CloseHandle.argtypes = [ctypes.c_void_p]
        handle = kernel.OpenProcess(0x1000, False, pid)
        if not handle:
            return False
        try:
            code = ctypes.c_uint32()
            return bool(kernel.GetExitCodeProcess(handle, ctypes.byref(code))) and code.value == 259
        finally:
            kernel.CloseHandle(handle)
    try:
        state = Path(f"/proc/{pid}/stat")
        if state.exists() and state.read_text().split(") ", 1)[1].startswith("Z"):
            return False
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False


class CommandChecks(unittest.TestCase):
    def test_arguments_and_exit_status(self):
        with tempfile.TemporaryDirectory(prefix="command check ") as temporary:
            fixture = Path(temporary) / "argument echo.py"
            fixture.write_text("import json, sys\nprint(json.dumps(sys.argv[1:]))\nsys.exit(7)\n")
            arguments = ["path with spaces", "a'b", 'a"b', "$(literal)", "`literal`", "a&b"]
            result = subprocess.run([sys.executable, RUNNER, "--timeout", "10", sys.executable,
                                     fixture, *arguments], capture_output=True, text=True, timeout=20)
            self.assertEqual(result.returncode, 7)
            self.assertEqual(json.loads(result.stdout), arguments)

    def test_timeout_stops_descendants(self):
        with tempfile.TemporaryDirectory(prefix="deadline check ") as temporary:
            directory = Path(temporary)
            sleeper = directory / "sleep.py"
            sleeper.write_text("import time\ntime.sleep(60)\n")
            parent = directory / "spawn.py"
            pid_file = directory / "child.pid"
            parent.write_text("import pathlib, subprocess, sys, time\n"
                              "p = subprocess.Popen([sys.executable, sys.argv[1]])\n"
                              "pathlib.Path(sys.argv[2]).write_text(str(p.pid))\n"
                              "time.sleep(60)\n")
            started = time.monotonic()
            result = subprocess.run([sys.executable, RUNNER, "--timeout", "2", sys.executable,
                                     parent, sleeper, pid_file], capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 124, result.stderr)
            self.assertLess(time.monotonic() - started, 15)
            self.assertTrue(pid_file.is_file())
            child = int(pid_file.read_text())
            self.assertFalse(alive(child), f"Child process {child} survived the deadline")


if __name__ == "__main__":
    unittest.main()
