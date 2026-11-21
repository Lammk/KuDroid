#!/usr/bin/env python3
"""Build and run POSIX regressions from Windows through WSL."""

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("deadline", ROOT / "scripts/run-command.py")
deadline = importlib.util.module_from_spec(spec)
spec.loader.exec_module(deadline)


class USBConnectionError(RuntimeError):
    returncode = 75


class USBDeploymentError(USBConnectionError):
    returncode = 76


def command(parts, seconds=240, cwd=None, **kwargs):
    parts = [str(part) for part in parts]
    print("==> " + subprocess.list2cmdline(parts), flush=True)
    code = deadline.run(parts, seconds, cwd=cwd, **kwargs)
    if code:
        raise subprocess.CalledProcessError(code, parts)


def output(parts):
    return subprocess.check_output([str(p) for p in parts], timeout=30).decode("utf-8").strip()


def require(names):
    missing = [name for name in names if not shutil.which(name)]
    if missing:
        raise RuntimeError("Missing tools: " + ", ".join(missing) + ". Run setup-windows.ps1 first.")


def relay_address(args, wsl):
    relay = Path.home() / ".kudroid/usbmux-relay.json"
    if not relay.is_file():
        return None
    configuration = json.loads(relay.read_text(encoding="utf-8-sig"))
    if configuration["Distribution"] != args.distribution:
        return None
    if args.action == "ios" and args.run:
        routes = json.loads(output([*wsl, "ip", "-json", "route", "list", "default"]))
        gateway = routes[0]["gateway"]
        guest = output([*wsl, "hostname", "-I"]).split()[0]
        if (configuration["Address"].rsplit(":", 1)[0] != gateway or
                configuration.get("GuestAddress", guest) != guest):
            raise USBConnectionError(
                f"WSL USB relay is stale (saved {configuration['Address']}, "
                f"current gateway {gateway}, guest {guest}). "
                "In Administrator PowerShell, run "
                f'.\\scripts\\connect-iphone.ps1 -Distribution "{args.distribution}", '
                "then rerun the build command.")
    return configuration["Address"]


def check_usb_device():
    import tempfile
    require(["xtool"])
    with tempfile.TemporaryFile() as discovery:
        try:
            command(["xtool", "devices", "--usb", "--no-wait"], 30,
                    stdout=discovery, stderr=subprocess.STDOUT)
        except subprocess.CalledProcessError as error:
            discovery.seek(0)
            detail = discovery.read().decode("utf-8", errors="replace").strip()
            raise USBConnectionError(
                f"USB device discovery failed: {detail or error}. "
                "If using the Windows USB relay, run scripts\\connect-iphone.ps1 "
                "in Administrator PowerShell for the selected distribution to refresh it.") from error
        discovery.seek(0)
        devices = discovery.read().decode("utf-8", errors="replace").strip()
    if not devices:
        raise USBConnectionError("No USB device connected. Connect and unlock the phone, accept Trust This Computer, "
                                 "and configure the Windows USB relay or WSL USB passthrough before using -Run.")
    print(devices, flush=True)


def repair_usb_relay(distribution):
    print("Refreshing the Windows USB relay; approve the administrator prompt if shown.", flush=True)
    command(["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
             ROOT / "scripts/connect-iphone.ps1", "-Distribution", distribution, "-Elevate"], 180)


def forward_workflow(args, wsl, linux_root, forwarded):
    usb_run = args.action == "ios" and args.run
    clean_consumed = False
    for attempt in range(2 if usb_run else 1):
        try:
            address = relay_address(args, wsl)
        except USBConnectionError as error:
            if not usb_run or attempt:
                raise
            print(error, flush=True)
        else:
            options = [option for option in forwarded if not (clean_consumed and option == "--clean")]
            if address:
                options.extend(["--usbmux-address", address])
            # Each Linux step has its own deadline, including descendants.
            result = subprocess.run([*wsl, "python3", linux_root + "/scripts/windows-workflow.py", *options],
                                    timeout=max(args.toolchain_timeout + 3600,
                                                args.build_timeout * 20 + args.test_timeout * 100))
            if (not usb_run or result.returncode not in (USBConnectionError.returncode,
                                                        USBDeploymentError.returncode) or attempt):
                return result.returncode
            clean_consumed = result.returncode == USBDeploymentError.returncode
        repair_usb_relay(args.distribution)


def run_ios_app(app, configuration, seconds):
    try:
        command(["xtool", "dev", "run", "--usb", "-c", configuration], seconds, cwd=app)
    except subprocess.CalledProcessError:
        # A failed connection requests relay repair; other failures retain their exit status.
        try:
            check_usb_device()
        except USBConnectionError as error:
            raise USBDeploymentError(str(error)) from error
        raise


def forward(args):
    require(["wsl.exe"])
    listing = subprocess.check_output(["wsl.exe", "--list", "--quiet"], timeout=30)
    names = listing.decode("utf-16-le" if b"\0" in listing else "utf-8").splitlines()
    if args.distribution not in [n.strip() for n in names]:
        raise RuntimeError(f"Install and initialize {args.distribution} first: "
                           f"wsl --install -d {args.distribution}. See WINDOWS.md.")
    wsl = ["wsl.exe", "--distribution", args.distribution, "--exec", "/usr/bin/env"]
    linux_root = output([*wsl, "wslpath", "-a", "-u", ROOT])
    if args.action == "setup":
        root_wsl = ["wsl.exe", "--distribution", args.distribution, "--user", "root", "--exec", "/usr/bin/env"]
        command([*root_wsl, "timeout", "--kill-after=10", "240", "apt-get", "update"], 260)
        command([*root_wsl, "timeout", "--kill-after=10", "1200", "env", "DEBIAN_FRONTEND=noninteractive",
                 "apt-get", "install", "-y", "--no-install-recommends", "build-essential", "cmake",
                 "ninja-build", "clang", "llvm", "lld", "git", "rsync", "curl", "ca-certificates",
                 "python3", "python3-venv", "openjdk-17-jdk-headless", "zlib1g-dev", "libsqlite3-dev",
                 "libssl-dev", "libminizip-dev", "libcurl4-openssl-dev", "libxml2-dev", "libedit2",
                 "gnupg", "gnupg2", "pkg-config", "libatomic1", "libicu-dev", "libuuid1",
                 "binutils-gold", "unzip", "zip", "libpython3-dev", "libncurses-dev", "libz3-dev",
                 "libegl1", "libgles2", "libegl-mesa0", "libgl1-mesa-dri",
                 "libncurses6", "libfuse2t64", "usbmuxd", "libimobiledevice-utils", "ifuse",
                 "gcc-aarch64-linux-gnu", "g++-aarch64-linux-gnu", "qemu-user"], 1220)
    forwarded = [args.action, "--linux-source", linux_root,
                 "--gles-backend", args.gles_backend, "--jobs", str(args.jobs),
                 "--build-timeout", str(args.build_timeout), "--test-timeout", str(args.test_timeout),
                 "--toolchain-timeout", str(args.toolchain_timeout), "--suite", args.suite]
    if args.configuration:
        forwarded.extend(["--configuration", args.configuration])
    for option in ("clean", "run", "skip_build", "configure"):
        if getattr(args, option):
            forwarded.append("--" + option.replace("_", "-"))
    if args.xcode:
        forwarded.extend(["--xcode", output([*wsl, "wslpath", "-a", "-u", Path(args.xcode).resolve()])])
    return forward_workflow(args, wsl, linux_root, forwarded)


def linux_environment():
    prefixes = [Path.home() / ".local/bin", Path.home() / ".local/share/swiftly/bin"]
    os.environ["PATH"] = os.pathsep.join(map(str, prefixes)) + os.pathsep + os.environ["PATH"]
    os.environ["APPIMAGE_EXTRACT_AND_RUN"] = "1"


def setup(args):
    require(["curl", "tar", "timeout"])
    architecture = output(["uname", "-m"])
    if architecture not in ("x86_64", "aarch64"):
        raise RuntimeError(f"Unsupported tool architecture: {architecture}")
    directory = Path.home() / ".local/bin"
    directory.mkdir(parents=True, exist_ok=True)
    if not shutil.which("xtool"):
        temporary = directory / "xtool.download"
        command(["curl", "-fL", "--retry", "3", "--max-time", "240",
                 f"https://github.com/xtool-org/xtool/releases/latest/download/xtool-{architecture}.AppImage",
                 "-o", temporary], 260)
        temporary.chmod(0o755)
        temporary.replace(directory / "xtool")
    if not shutil.which("swiftly"):
        import tempfile
        with tempfile.TemporaryDirectory(prefix="kudroid-swiftly-") as temporary:
            archive = Path(temporary) / "swiftly.tar.gz"
            command(["curl", "-fL", "--retry", "3", "--max-time", "240",
                     f"https://download.swift.org/swiftly/linux/swiftly-{architecture}.tar.gz", "-o", archive], 260)
            command(["tar", "-xzf", archive, "-C", temporary], 120)
            command([Path(temporary) / "swiftly", "init", "--assume-yes", "--skip-install"], 240)
    command(["swiftly", "install", "6.4.0", "--assume-yes"], args.toolchain_timeout)
    command(["swiftly", "use", "6.4.0", "--global-default", "--assume-yes"], 120, cwd=Path.home())
    command(["swift", "--version"], 60)
    command(["xtool", "--help"], 60)
    if args.xcode:
        if not Path(args.xcode).is_file():
            raise RuntimeError(f"Xcode archive not found: {args.xcode}")
        command(["xtool", "sdk", "install", args.xcode], 1800)
    if args.configure:
        command(["xtool", "setup"], 1800)
    print("Tool installation complete. Run xtool setup interactively in WSL for Apple authentication.")


def workspace(source):
    import fcntl
    require(["rsync"])
    identity = hashlib.sha256(str(source).encode()).hexdigest()[:16]
    base = Path.home() / ".cache/kudroid-windows" / identity
    base.mkdir(parents=True, exist_ok=True)
    lock = (base / "workflow.lock").open("w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        raise RuntimeError("Another workflow is using this workspace")
    target = base / "source"
    if target.is_symlink() or target.resolve().parent != base.resolve():
        raise RuntimeError("Unsafe workspace path")
    target.mkdir(exist_ok=True)
    excluded = [".git", "/build/", "/build-*/", "/framework/build/*", ".build/", "xtool/", "libs/", "node_modules/",
                "logs*", ".cache", ".claude", ".freebuff", ".planning", "__pycache__",
                "third_party/angle-src", "third_party/flutter-runtime", "third_party/aosp",
                "third_party/art_src", "third_party/build-tools", "third_party/StikJIT",
                "src/ios-pairing/target", "sakayori-music", "androguard.db"]
    synchronization = ["rsync", "-a", "--delete", "--checksum", "--include=/framework/build/framework.dex",
                       *["--exclude=" + p for p in excluded],
                       str(source) + "/", str(target) + "/"]
    command(synchronization, 600)
    import tempfile
    with tempfile.TemporaryFile() as verification:
        command([*synchronization, "--dry-run", "--out-format=%i %n"], 600, stdout=verification)
        verification.seek(0)
        differences = [line for line in verification.read().decode("utf-8").splitlines()
                       if line.startswith((">f", "cL"))]
    if differences:
        raise RuntimeError("Build copy differs from source after synchronization: " + "; ".join(differences[:10]))
    if not (target / ".git").exists() and (source / ".git").exists():
        (target / ".git").symlink_to(source / ".git", target_is_directory=True)
    # Normalize executable shell inputs only in the build copy.
    for path in target.rglob("*.sh"):
        relative = path.relative_to(target)
        if relative.parts[0].startswith("build") or any(part in (".git", ".build") for part in relative.parts):
            continue
        data = path.read_bytes()
        if b"\r\n" in data:
            path.write_bytes(data.replace(b"\r\n", b"\n"))
        path.chmod(path.stat().st_mode | 0o111)
    return target, lock


def ios(args, root, source):
    require(["cmake", "ninja", "swift", "xtool", "llvm-ar"])
    native_configuration = (args.configuration or "release").capitalize()
    swift_configuration = args.configuration or "debug"
    sdks = list((Path.home() / ".swiftpm/swift-sdks").glob(
        "darwin.artifactbundle/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS*.sdk"))
    if not sdks:
        raise RuntimeError("Apple iOS SDK missing. Download Xcode.xip and run xtool setup in WSL.")
    build = root / "build-ios-windows"
    app = root / "ios-app/KuDroidShell"
    if args.clean:
        for path in (build, app / ".build", app / "xtool"):
            if path.is_symlink() or not path.resolve().is_relative_to(root.resolve()):
                raise RuntimeError(f"Unsafe clean path: {path}")
            if path.exists():
                shutil.rmtree(path)
    command(["python3", root / "scripts/flutter-runtime/verify-asset.py", "--asset", app / "Resources/runtime"], 120)
    command(["python3", root / "scripts/verify-system-fonts.py"], 120)
    command(["cmake", "-S", root, "-B", build, "-G", "Ninja",
             "-DCMAKE_TOOLCHAIN_FILE=" + str(root / "cmake/ios-linux-toolchain.cmake"),
             "-DCMAKE_BUILD_TYPE=" + native_configuration,
             "-DKUDROID_GLES_BACKEND=" + args.gles_backend], args.build_timeout)
    command(["cmake", "--build", build, "--target", "kudroid_core", "--parallel", args.jobs], args.build_timeout)
    (app / "libs").mkdir(exist_ok=True)
    libraries = [build / "libkudroid_core.a", build / "third_party/art_dex/libart_dex.a",
                 build / "_deps/libvpx-build/libvpx.a", build / "libkudroid_vorbis.a",
                 build / "_deps/ogg-build/libogg.a"]
    if any(not library.is_file() for library in libraries):
        raise RuntimeError("A required native archive was not built")
    archive = app / "libs/libkudroid_core_combined.a"
    recipe = "create " + str(archive) + "\n" + "".join("addlib " + str(p) + "\n" for p in libraries) + "save\nend\n"
    import tempfile
    with tempfile.TemporaryFile() as input_file:
        input_file.write(recipe.encode())
        input_file.seek(0)
        command(["llvm-ar", "-M"], 120, stdin=input_file)
    command(["python3", root / "scripts/build-ios-jit.py", "--sdk", sdks[-1]], 1500)
    shutil.copy2(root / "src/ios-pairing/Cargo.lock", source / "src/ios-pairing/Cargo.lock")
    notices = "ios-app/KuDroidShell/Resources/licenses/JIT-NOTICES.txt"
    (source / notices).parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(root / notices, source / notices)
    if args.run:
        run_ios_app(app, swift_configuration, args.build_timeout)
        return
    command(["xtool", "dev", "build", "--ipa", "-c", swift_configuration], args.build_timeout, cwd=app)
    ipa = app / "xtool/KuDroidShell.ipa"
    command(["python3", root / "scripts/build-ios-jit.py", "--ipa", ipa], 120)
    command(["python3", root / "scripts/embed_standalone_launcher.py", ipa], 120)
    command(["python3", root / "scripts/verify-ios-jit.py", ipa], 120)
    command(["python3", root / "scripts/flutter-runtime/verify-asset.py", ipa], 120)
    command(["python3", root / "scripts/verify-system-fonts.py", ipa], 120)
    source_archive = app / "xtool/KuDroid-framework-source.zip"
    command(["python3", root / "scripts/package-framework-source.py", source_archive], 120)
    destination = source / "ios-app/KuDroidShell/xtool/KuDroidShell.ipa"
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(ipa, destination)
    shutil.copy2(source_archive, destination.parent / source_archive.name)
    print(f"IPA copied to Windows checkout: {destination}")


def tests(args, root):
    require(["cmake", "ninja", "c++", "javac", "java"])
    build = root / "build-host-windows"
    suite = args.suite
    if suite in ("all", "core", "framework", "arm64") and not args.skip_build:
        command(["cmake", "-S", root, "-B", build, "-G", "Ninja",
                 "-DCMAKE_BUILD_TYPE=Release", "-DKUDROID_BUILD_HOST_TESTS=OFF"], args.build_timeout)
        command(["cmake", "--build", build, "--parallel", args.jobs], args.build_timeout)
    if suite in ("all", "core"):
        binaries = sorted(p for p in build.glob("test_*") if p.is_file() and os.access(p, os.X_OK)
                          and p.name not in ("test_framework_startup", "test_surface_lifecycle",
                                             "test_manifest_services", "test_kuart_android_tls", "test_native_callbacks"))
        if not binaries:
            raise RuntimeError("No host test binaries found")
        for binary in binaries:
            extra = [binary.name.removeprefix("test_egl_backend_")] if binary.name.startswith("test_egl_backend_") else []
            if binary.name in ("test_android_tts", "test_interpreter_entry_lock"):
                extra = [root / "framework/build/framework.dex"]
            command([binary, *extra], args.test_timeout, cwd=build)
    if suite in ("all", "framework"):
        for name in ("test-framework-startup", "test-framework-modules", "test-surface-lifecycle", "test-native-callbacks"):
            extra = [] if name == "test-framework-modules" else ["--skip-build"]
            command(["python3", root / f"scripts/{name}.py", "--build-dir", build, *extra],
                    max(600, args.test_timeout), cwd=root)
        command(["python3", root / "scripts/test-android-tls.py", "--build-dir", build],
                max(600, args.build_timeout), cwd=root)
    if suite in ("all", "posix"):
        for name in ("test-native-looper-bridge", "test-guest-altstack"):
            command(["python3", root / f"scripts/{name}.py"], args.test_timeout, cwd=root)
        require(["swiftc"])
        information = json.loads(output(["swiftc", "-print-target-info"]))
        swift_root = Path(information["paths"]["runtimeResourcePath"]).parents[1]
        command(["python3", root / "scripts/test-timerfd-deadlines.py", "--swift-root", swift_root],
                args.test_timeout, cwd=root)
    if suite in ("all", "arm64"):
        require(["aarch64-linux-gnu-gcc", "aarch64-linux-gnu-g++"])
        if not (shutil.which("qemu-aarch64-static") or shutil.which("qemu-aarch64")):
            raise RuntimeError("Install qemu-user to run the ARM64 regressions")
        if not (build / "CMakeFiles/kudroid_core.dir/src/kuart/JitCompiler.cpp.o").is_file():
            raise RuntimeError("Build the host core before running ARM64 regressions")
        for name in ("test-trampoline-arm64", "test-vararg-arm64", "test-jit-arm64"):
            command(["bash", root / f"scripts/{name}.sh", build], args.test_timeout, cwd=root)
    if suite == "probes":
        require(["aarch64-linux-gnu-gcc", "aarch64-linux-gnu-readelf"])
        if not any((root / "tests/so").glob("*.c")):
            raise RuntimeError("Guest probe sources missing: restore tests/so/*.c before running this suite")
        command(["bash", root / "scripts/build-test-so.sh"], args.build_timeout, cwd=root)
    print(f"Completed regression suite: {suite}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("setup", "ios", "test"))
    parser.add_argument("--distribution", default="Ubuntu-26.04")
    parser.add_argument("--linux-source", type=Path)
    parser.add_argument("--configuration", choices=("debug", "release"))
    parser.add_argument("--gles-backend", choices=("metal", "vulkan"), default="metal")
    parser.add_argument("--jobs", type=int, default=min(os.cpu_count() or 2, 6))
    parser.add_argument("--build-timeout", type=int, default=600)
    parser.add_argument("--test-timeout", type=int, default=240)
    parser.add_argument("--toolchain-timeout", type=int, default=3600)
    parser.add_argument("--suite", choices=("all", "core", "framework", "posix", "arm64", "probes"), default="all")
    parser.add_argument("--clean", action="store_true")
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--skip-build", action="store_true")
    parser.add_argument("--configure", action="store_true")
    parser.add_argument("--xcode")
    parser.add_argument("--usbmux-address")
    args = parser.parse_args()
    if min(args.jobs, args.build_timeout, args.test_timeout, args.toolchain_timeout) <= 0:
        parser.error("Jobs and timeouts must be positive")
    if os.name == "nt":
        return forward(args)
    linux_environment()
    if args.usbmux_address:
        os.environ["USBMUXD_SOCKET_ADDRESS"] = args.usbmux_address
    if args.action == "setup":
        setup(args)
        return 0
    if args.linux_source is None:
        parser.error("--linux-source is required inside WSL")
    if args.action == "ios" and args.run:
        check_usb_device()
    root, lock = workspace(args.linux_source)
    try:
        if args.action == "ios":
            ios(args, root, args.linux_source)
        else:
            tests(args, root)
            if args.suite == "probes":
                shutil.copytree(root / "build/test-so", args.linux_source / "build/test-so", dirs_exist_ok=True)
    finally:
        lock.close()
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (RuntimeError, OSError, subprocess.SubprocessError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        sys.exit(getattr(error, "returncode", 1))
