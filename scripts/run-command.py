#!/usr/bin/env python3
"""Run a command with a deadline and stop its process tree on timeout."""

import argparse
import os
import signal
import subprocess
import sys


def run(command, seconds, **kwargs):
    if seconds <= 0:
        raise ValueError("Timeout must be positive")
    process = subprocess.Popen(command, start_new_session=os.name != "nt", **kwargs)
    try:
        return process.wait(timeout=seconds)
    except (subprocess.TimeoutExpired, KeyboardInterrupt):
        if os.name == "nt":
            subprocess.run(["taskkill.exe", "/PID", str(process.pid), "/T", "/F"],
                           timeout=30, stdout=subprocess.DEVNULL, check=False)
        else:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        process.wait(timeout=30)
        print(f"Command stopped after timeout or interruption ({seconds}s)", file=sys.stderr)
        return 124


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--timeout", type=int, default=240)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command
    if command[:1] == ["--"]:
        command = command[1:]
    if not command:
        parser.error("A command is required")
    return run(command, args.timeout)


if __name__ == "__main__":
    sys.exit(main())
