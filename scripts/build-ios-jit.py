#!/usr/bin/env python3
"""Build the pairing library and debugger extension for iOS."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import struct
import subprocess
import sys
import tempfile
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
VERSION = "1.9.0"
DIGEST = "806664393770c68e75f2b6429955bfdd88cfaad09fec2ba70f8ed615ff90c060"


def run(args, seconds=240, **kwargs):
    subprocess.run([str(x) for x in args], check=True, timeout=seconds, **kwargs)


def download(url):
    return urllib.request.urlopen(url, timeout=60).read()


def framework_metadata(framework):
    metadata = framework / "Info.plist"
    if metadata.is_file():
        return
    binary = (framework / "StikJIT").read_bytes()
    if binary[:4] != b"\xcf\xfa\xed\xfe":
        raise RuntimeError("Expected an ARM64 framework executable")
    position = 32
    minimum = None
    for _ in range(struct.unpack_from("<I", binary, 16)[0]):
        command, size = struct.unpack_from("<II", binary, position)
        if size < 8 or position + size > len(binary):
            raise RuntimeError("Invalid framework load command")
        if command == 0x32:
            if size < 24 or struct.unpack_from("<I", binary, position + 8)[0] != 2:
                raise RuntimeError("Expected an iOS device framework")
            version = struct.unpack_from("<I", binary, position + 12)[0]
            minimum = f"{version >> 16}.{(version >> 8) & 255}.{version & 255}"
        position += size
    if minimum is None:
        raise RuntimeError("Framework deployment target is missing")
    metadata.write_bytes(plistlib.dumps({
        "CFBundleDevelopmentRegion": "en",
        "CFBundleExecutable": "StikJIT",
        "CFBundleIdentifier": "org.stikdebug.StikJIT",
        "CFBundleInfoDictionaryVersion": "6.0",
        "CFBundleName": "StikJIT",
        "CFBundlePackageType": "FMWK",
        "CFBundleShortVersionString": VERSION,
        "CFBundleVersion": VERSION,
        "CFBundleSupportedPlatforms": ["iPhoneOS"],
        "MinimumOSVersion": minimum,
    }))


def prepare_framework():
    destination = ROOT / "third_party/StikJIT"
    framework = destination / "StikJIT.xcframework/ios-arm64/StikJIT.framework"
    marker = destination / "version.txt"
    if marker.is_file() and marker.read_text().strip() == DIGEST and framework.is_dir():
        framework_metadata(framework)
        return framework
    destination.mkdir(parents=True, exist_ok=True)
    data = download(f"https://github.com/StikDebug/StikJIT/releases/download/{VERSION}/StikJIT.xcframework.zip")
    if hashlib.sha256(data).hexdigest() != DIGEST:
        raise RuntimeError("StikJIT release checksum does not match")
    with tempfile.TemporaryDirectory(prefix="stikjit-", dir=destination) as temporary:
        archive = Path(temporary) / "framework.zip"
        archive.write_bytes(data)
        unpacked = Path(temporary) / "unpacked"
        with zipfile.ZipFile(archive) as source:
            for name in source.namelist():
                target = (unpacked / name).resolve()
                if not target.is_relative_to(unpacked.resolve()):
                    raise RuntimeError("Invalid framework archive path")
            source.extractall(unpacked)
        source_framework = next(unpacked.rglob("StikJIT.xcframework"))
        for script in source_framework.rglob("*.js"):
            if script.name not in ("universal.js", "legacy.js"):
                raise RuntimeError("Unexpected bundled script")
            script.unlink()
        for signature in source_framework.rglob("_CodeSignature"):
            if not signature.resolve().is_relative_to(source_framework.resolve()):
                raise RuntimeError("Invalid framework signature path")
            shutil.rmtree(signature)
        target = destination / "StikJIT.xcframework"
        if target.exists():
            if not target.resolve().is_relative_to(ROOT.resolve()):
                raise RuntimeError("Invalid framework output path")
            shutil.rmtree(target)
        shutil.copytree(source_framework, target)
    marker.write_text(DIGEST + "\n")
    framework_metadata(framework)
    return framework


def notices(crate, environment):
    metadata = json.loads(subprocess.check_output(
        [str(Path.home() / ".cargo/bin/cargo") if (Path.home() / ".cargo/bin/cargo").exists() else "cargo",
         "metadata", "--locked", "--filter-platform", "aarch64-apple-ios", "--format-version", "1", "--manifest-path", str(crate / "Cargo.toml")],
        env=environment, timeout=120))
    parts = [f"StikJIT {VERSION}\nSource: https://github.com/StikDebug/StikJIT/tree/{VERSION}\n"
             "The framework is repackaged without its upstream scripts. The helper uses an independently written MIT script.\n",
             download(f"https://raw.githubusercontent.com/StikDebug/StikJIT/{VERSION}/LICENSE").decode()]
    active = {node["id"] for node in metadata["resolve"]["nodes"]}
    packages = [package for package in metadata["packages"] if package["id"] in active]
    for package in sorted(packages, key=lambda p: (p["name"], p["version"])):
        license_name = package.get("license") or ""
        choices = [part for part in license_name.split(" OR ") if "GPL" not in part.upper()]
        if not choices:
            raise RuntimeError("Unsupported dependency license: " + package["name"])
        parts.append(f"\n{package['name']} {package['version']}\nLicense: {license_name}\n"
                     f"Selected license: {choices[0]}\n"
                     f"Source: {package.get('repository') or 'https://crates.io/crates/' + package['name']}\n")
        directory = Path(package["manifest_path"]).parent
        files = sorted({p for pattern in ("LICENSE*", "COPYING*", "LICENCE*", "license*")
                        for p in directory.glob(pattern) if p.is_file()})
        for path in files:
            parts.append(path.read_text(errors="replace"))
    output = ROOT / "ios-app/KuDroidShell/Resources/licenses/JIT-NOTICES.txt"
    output.parent.mkdir(parents=True, exist_ok=True)
    text = "\n".join(parts)
    output.write_text("\n".join(line.rstrip() for line in text.splitlines()) + "\n", encoding="utf-8")


def build(sdk):
    framework = prepare_framework()
    crate = ROOT / "src/ios-pairing"
    cargo = Path.home() / ".cargo/bin/cargo"
    cargo = str(cargo) if cargo.is_file() else "cargo"
    environment = os.environ.copy()
    environment["SDKROOT"] = str(sdk)
    environment["IPHONEOS_DEPLOYMENT_TARGET"] = "15.0"
    environment["CC_aarch64_apple_ios"] = "clang"
    environment["AR_aarch64_apple_ios"] = "llvm-ar"
    environment["CFLAGS_aarch64_apple_ios"] = f"--target=arm64-apple-ios15.0 -isysroot {sdk}"
    if not (crate / "Cargo.lock").exists():
        run([cargo, "generate-lockfile", "--manifest-path", crate / "Cargo.toml"], 180, env=environment)
    run([cargo, "build", "--release", "--locked", "-j1", "--target", "aarch64-apple-ios",
         "--manifest-path", crate / "Cargo.toml"], 1200, env=environment)
    libraries = ROOT / "ios-app/KuDroidShell/libs"
    libraries.mkdir(exist_ok=True)
    target = Path(environment.get("CARGO_TARGET_DIR", crate / "target"))
    shutil.copy2(target / "aarch64-apple-ios/release/libkudroid_pairing.a", libraries / "libkudroid_pairing.a")
    notices(crate, environment)
    if sys.platform != "darwin":
        print("Pairing library and framework ready; the build tool packages the helper extension product.")
        return
    output = ROOT / "build-ios-jit/KuDroidJITHelper.appex"
    output.mkdir(parents=True, exist_ok=True)
    swift_options = []
    artifact = next((parent for parent in sdk.parents if (parent / "swift-sdk.json").is_file()), None)
    if artifact:
        configuration = json.loads((artifact / "swift-sdk.json").read_text())["targetTriples"]["arm64-apple-ios"]
        swift_options += ["-resource-dir", artifact / configuration["swiftResourcesPath"]]
        for path in configuration.get("includeSearchPaths", []): swift_options += ["-I", artifact / path]
        for path in configuration.get("librarySearchPaths", []): swift_options += ["-L", artifact / path]
        swift_options += ["-tools-directory", artifact / "toolset/bin", "-use-ld=lld",
                          "-Xfrontend", "-enable-cross-import-overlays"]
    notification_headers = ROOT / "ios-app/KuDroidShell/JITNotifications/include"
    with tempfile.TemporaryDirectory(prefix="jit-notifications-", dir=output.parent) as temporary:
        notification_object = Path(temporary) / "notifications.o"
        run(["clang", "-target", "arm64-apple-ios26.0", "-isysroot", sdk,
             "-I", notification_headers, "-c", ROOT / "ios-app/KuDroidShell/JITNotifications/JITNotifications.c",
             "-o", notification_object], 120)
        run(["swiftc", "-parse-as-library", "-emit-executable", "-application-extension",
             "-module-name", "KuDroidJITHelper", "-target", "arm64-apple-ios26.0", "-sdk", sdk,
             *swift_options, "-I", notification_headers, notification_object,
             "-F", framework.parent, "-framework", "StikJIT", "-framework", "Foundation",
             "-Xlinker", "-e", "-Xlinker", "_NSExtensionMain",
             "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../../Frameworks",
             ROOT / "ios-app/KuDroidShell/JITProtocol/JITMessages.swift", ROOT / "ios-app/KuDroidShell/JITHelper/JITService.swift",
             "-o", output / "KuDroidJITHelper"], 240)
    shutil.copy2(ROOT / "ios-app/KuDroidShell/JITHelper/Info.plist", output / "Info.plist")
    shutil.copy2(ROOT / "ios-app/KuDroidShell/JITHelper/jit-bootstrap.js", output / "jit-bootstrap.js")
    print("Built isolated pairing library and JIT helper.")


def configure_info(info, signing_identifier=None):
    identifier = signing_identifier or info["CFBundleIdentifier"]
    types = [item for item in info.get("CFBundleURLTypes", []) if item.get("CFBundleURLName") != "JIT Setup"]
    types.append({"CFBundleURLName": "JIT Setup", "CFBundleURLSchemes":
                  ["kudroid-jit-" + identifier.replace(".", "-").lower()]})
    info["CFBundleURLTypes"] = types
    schemes = set(info.get("LSApplicationQueriesSchemes", []))
    info["LSApplicationQueriesSchemes"] = sorted(schemes | {"stikdebug", "apple-magnifier", "localdevvpn"})
    services = set(info.get("NSBonjourServices", []))
    info["NSBonjourServices"] = sorted(services | {"_remotepairing-pairable-host._tcp"})
    info["BGTaskSchedulerPermittedIdentifiers"] = [identifier + ".pairing.session"]
    return info


def embed(app, signing_identifier=None):
    info_path = app / "Info.plist"
    info = configure_info(plistlib.loads(info_path.read_bytes()), signing_identifier)
    info_path.write_bytes(plistlib.dumps(info))
    framework = prepare_framework()
    helper = app / "PlugIns/KuDroidJITHelper.appex"
    if not helper.is_dir():
        source = ROOT / "build-ios-jit/KuDroidJITHelper.appex"
        if not (source / "KuDroidJITHelper").is_file(): raise RuntimeError("Build the app with its JIT extension product")
        helper.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(source, helper)
    for source, destination in [(framework, app / "Frameworks/StikJIT.framework")]:
        destination.parent.mkdir(parents=True, exist_ok=True)
        if destination.exists():
            if not destination.resolve().is_relative_to(app.resolve()):
                raise RuntimeError("Invalid bundle destination")
            shutil.rmtree(destination)
        shutil.copytree(source, destination)
    nested = helper / "Frameworks/StikJIT.framework"
    if nested.exists():
        if not nested.resolve().is_relative_to(helper.resolve()):
            raise RuntimeError("Invalid extension framework path")
        shutil.rmtree(nested)
    plugin = helper / "Info.plist"
    child = plistlib.loads(plugin.read_bytes())
    child["CFBundleIdentifier"] = info["CFBundleIdentifier"] + ".JITHelper"
    plugin.write_bytes(plistlib.dumps(child))
    for metadata in app.rglob("Info.plist"):
        bundle_info = plistlib.loads(metadata.read_bytes())
        executable = bundle_info.get("CFBundleExecutable")
        if executable:
            if Path(executable).name != executable:
                raise RuntimeError("Invalid bundle executable name")
            binary = metadata.parent / executable
            if binary.is_file(): binary.chmod(0o755)
    print("Embedded debugger extension and isolated framework.")


def embed_ipa(ipa, signing_identifier=None):
    with tempfile.TemporaryDirectory(prefix="kudroid-jit-package-") as directory:
        temporary = Path(directory)
        with zipfile.ZipFile(ipa) as archive:
            for name in archive.namelist():
                if not (temporary / name).resolve().is_relative_to(temporary.resolve()):
                    raise RuntimeError("Invalid IPA path")
            archive.extractall(temporary)
            for entry in archive.infolist():
                path = temporary / entry.filename
                mode = (entry.external_attr >> 16) & 0o777
                if mode and path.exists(): path.chmod(mode)
        apps = list((temporary / "Payload").glob("*.app"))
        if len(apps) != 1:
            raise RuntimeError("Expected one app bundle")
        embed(apps[0], signing_identifier)
        output = temporary / "rebuilt.ipa"
        with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
            for file in (temporary / "Payload").rglob("*"):
                if file.is_file(): archive.write(file, file.relative_to(temporary).as_posix())
        shutil.copy2(output, ipa)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sdk", type=Path)
    parser.add_argument("--app", type=Path)
    parser.add_argument("--ipa", type=Path)
    parser.add_argument("--signing-bundle-id", help="Final signing identifier for pairing metadata")
    args = parser.parse_args()
    if args.signing_bundle_id and not (args.app or args.ipa):
        parser.error("--signing-bundle-id requires --app or --ipa")
    if args.app: embed(args.app, args.signing_bundle_id)
    elif args.ipa: embed_ipa(args.ipa, args.signing_bundle_id)
    elif args.sdk:
        sdk = args.sdk
        if str(sdk) == "iphoneos":
            sdk = Path(subprocess.check_output(["xcrun", "--sdk", "iphoneos", "--show-sdk-path"], timeout=30).decode().strip())
        if not sdk.is_dir(): raise RuntimeError("The iOS SDK path does not exist")
        build(sdk.resolve())
    else: parser.error("Provide --sdk, --app, or --ipa")


if __name__ == "__main__":
    main()
