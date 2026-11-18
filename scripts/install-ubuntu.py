#!/usr/bin/env python3
"""Import an official Ubuntu WSL image and configure a normal default user."""

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import urllib.request
import winreg


HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("deadline", HERE / "run-command.py")
deadline = importlib.util.module_from_spec(spec)
spec.loader.exec_module(deadline)


def output(command):
    raw = subprocess.check_output([str(p) for p in command], timeout=60)
    return raw.decode("utf-16-le" if b"\0" in raw else "utf-8").strip()


def run(command, seconds=240):
    result = deadline.run([str(p) for p in command], seconds)
    if result:
        raise subprocess.CalledProcessError(result, command)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--distribution", default="Ubuntu-26.04")
    parser.add_argument("--user", default="kudroid")
    parser.add_argument("--archive", type=Path)
    args = parser.parse_args()
    if os.name != "nt":
        parser.error("Run this installer on Windows")
    if not re.fullmatch(r"[a-z][a-z0-9_-]{0,30}", args.user):
        parser.error("Use a lowercase Linux user name")
    names = output(["wsl.exe", "--list", "--quiet"]).splitlines()
    if args.distribution in [n.strip() for n in names]:
        print(f"{args.distribution} is already installed")
        return
    request = urllib.request.Request(
        "https://raw.githubusercontent.com/microsoft/WSL/master/distributions/DistributionInfo.json",
        headers={"User-Agent": "WSL-setup"})
    with urllib.request.urlopen(request, timeout=30) as response:
        manifest = json.load(response)
    entries = [entry for group in manifest["ModernDistributions"].values() for entry in group]
    entry = next((e for e in entries if e["Name"] == args.distribution), None)
    if entry is None:
        raise RuntimeError(f"No official WSL image found for {args.distribution}")
    arch = "Arm64Url" if os.environ.get("PROCESSOR_ARCHITECTURE", "").upper() == "ARM64" else "Amd64Url"
    image = entry[arch]
    base = Path.home() / ".kudroid"
    archive = args.archive or base / "downloads" / Path(image["Url"]).name
    archive.parent.mkdir(parents=True, exist_ok=True)
    if args.archive is None:
        run(["curl.exe", "-fL", "--retry", "3", "--connect-timeout", "20", "--max-time", "1150",
             "--continue-at", "-", image["Url"], "-o", archive], 1200)
    digest = hashlib.sha256()
    with archive.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    if digest.hexdigest() != image["Sha256"]:
        raise RuntimeError("Ubuntu image checksum does not match the official WSL manifest")
    target = base / "wsl" / args.distribution
    if target.exists() and any(target.iterdir()):
        raise RuntimeError(f"Installation directory is not empty: {target}")
    if target.is_symlink() or not target.resolve().is_relative_to(base.resolve()):
        raise RuntimeError("Unsafe WSL installation directory")
    target.mkdir(parents=True, exist_ok=True)
    run(["wsl.exe", "--import", args.distribution, target, archive, "--version", "2"], 600)
    wsl = ["wsl.exe", "--distribution", args.distribution, "--user", "root", "--exec", "/usr/bin/env"]
    run([*wsl, "useradd", "--create-home", "--shell", "/bin/bash", "--groups", "sudo", args.user], 120)
    uid = int(output([*wsl, "id", "-u", args.user]))
    registry_path = r"Software\Microsoft\Windows\CurrentVersion\Lxss"
    with winreg.OpenKey(winreg.HKEY_CURRENT_USER, registry_path) as distributions:
        for index in range(winreg.QueryInfoKey(distributions)[0]):
            name = winreg.EnumKey(distributions, index)
            with winreg.OpenKey(distributions, name, 0, winreg.KEY_READ | winreg.KEY_SET_VALUE) as key:
                if winreg.QueryValueEx(key, "DistributionName")[0] == args.distribution:
                    winreg.SetValueEx(key, "DefaultUid", 0, winreg.REG_DWORD, uid)
                    break
        else:
            raise RuntimeError("Imported distribution registration was not found")
    run(["wsl.exe", "--terminate", args.distribution], 60)
    run(["wsl.exe", "--distribution", args.distribution, "--exec", "/usr/bin/id"], 60)
    print(f"Installed {args.distribution}; default user: {args.user}.")
    print(f"Set a password later with: wsl -d {args.distribution} -u root -- passwd {args.user}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        sys.exit(getattr(error, "returncode", 1))
