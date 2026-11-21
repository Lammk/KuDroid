#!/usr/bin/env python3
"""Verify helper isolation, resources, and exported-app metadata in an IPA."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import struct
import zipfile


def dependencies(data):
    assert data[:4] == b"\xcf\xfa\xed\xfe", "expected arm64 Mach-O"
    position = 32
    result = []
    for _ in range(struct.unpack_from("<I", data, 16)[0]):
        command, size = struct.unpack_from("<II", data, position)
        assert size >= 8 and position + size <= len(data), "invalid load command"
        if command in (0xc, 0x80000018, 0x8000001f):
            offset = struct.unpack_from("<I", data, position + 8)[0]
            assert offset < size
            result.append(data[position + offset:position + size].split(b"\0")[0].decode())
        position += size
    return result


def verify(ipa, signing_identifier=None):
    root = Path(__file__).resolve().parents[1]
    with zipfile.ZipFile(ipa) as archive:
        names = archive.namelist()
        plists = [name for name in names if name.startswith("Payload/") and name.count("/") == 2 and name.endswith("/Info.plist")]
        assert len(plists) == 1
        parent = plists[0][:-len("Info.plist")]
        info = plistlib.loads(archive.read(plists[0]))
        assert info["MinimumOSVersion"] == "15.0", "main deployment target changed"
        binary_name = parent + info["CFBundleExecutable"]
        main = archive.read(binary_name)
        assert struct.unpack_from("<I", main, 12)[0] == 2
        assert not any("StikJIT.framework" in path for path in dependencies(main)), "main app strongly links the newer framework"
        assert archive.getinfo(binary_name).external_attr >> 16 & 0o111, "main executable permission missing"
        plugin = parent + "PlugIns/KuDroidJITHelper.appex/"
        child = plistlib.loads(archive.read(plugin + "Info.plist"))
        assert child["CFBundleIdentifier"] == info["CFBundleIdentifier"] + ".JITHelper"
        assert int(child["MinimumOSVersion"].split(".")[0]) >= 26
        assert child["NSExtension"]["NSExtensionPointIdentifier"] == "com.apple.ar.viewer"
        assert child["NSExtension"]["NSExtensionPrincipalClass"] == "KDJITService"
        assert child["NSExtension"]["NSExtensionContextClass"] == "NSExtensionContext"
        assert child["NSExtension"]["NSExtensionContextHostClass"] == "NSExtensionContext"
        assert child["NSExtension"]["NSExtensionAttributes"]["NSExtensionActivationRule"] == "FALSEPREDICATE"
        helper_name = plugin + child["CFBundleExecutable"]
        helper = archive.read(helper_name)
        assert struct.unpack_from("<I", helper, 12)[0] == 2
        assert b"KDJITService" in helper, "helper principal class was not linked"
        assert any("StikJIT.framework" in path for path in dependencies(helper)), "helper does not link its debugger framework"
        assert b"kudroid_post_jit_progress" in helper and b"app.jit.progress." in helper, "helper progress bridge missing"
        assert archive.getinfo(helper_name).external_attr >> 16 & 0o111, "helper executable permission missing"
        frameworks = {name.split(".framework/", 1)[0] + ".framework/"
                      for name in names if ".framework/" in name}
        for framework in frameworks:
            metadata = plistlib.loads(archive.read(framework + "Info.plist"))
            assert metadata["CFBundlePackageType"] == "FMWK", "invalid framework bundle type"
            assert metadata["CFBundleIdentifier"], "framework identifier missing"
            executable = metadata["CFBundleExecutable"]
            assert Path(executable).name == executable, "invalid framework executable name"
            assert archive.getinfo(framework + executable).external_attr >> 16 & 0o111, "framework executable permission missing"
        debugger_frameworks = [name for name in frameworks if name.endswith("/StikJIT.framework/")]
        assert debugger_frameworks == [parent + "Frameworks/StikJIT.framework/"], "debugger framework must be shared by the containing app"
        scripts = [name for name in names if name.endswith("/jit-bootstrap.js")]
        assert len(scripts) == 1 and scripts[0].startswith(plugin)
        expected = root / "ios-app/KuDroidShell/JITHelper/jit-bootstrap.js"
        assert archive.read(scripts[0]) == expected.read_bytes(), "packaged script differs from tested source"
        assert not any(name.endswith(("/universal.js", "/legacy.js")) for name in names), "upstream scripts were bundled"
        assert not any(name.endswith(("/pairing.plist", "/pairingFile.plist")) for name in names), "private pairing record in app bundle"
        notices = [name for name in names if name.endswith("/JIT-NOTICES.txt")]
        assert len(notices) == 1
        assert archive.read(notices[0]) == (root / "ios-app/KuDroidShell/Resources/licenses/JIT-NOTICES.txt").read_bytes()
        assert "localdevvpn" in info["LSApplicationQueriesSchemes"]
        assert "_remotepairing-pairable-host._tcp" in info["NSBonjourServices"]
        pairing_identifier = signing_identifier or info["CFBundleIdentifier"]
        assert info["BGTaskSchedulerPermittedIdentifiers"] == [pairing_identifier + ".pairing.session"]
        setup = [item for item in info["CFBundleURLTypes"] if item.get("CFBundleURLName") == "JIT Setup"]
        assert len(setup) == 1
        assert setup[0]["CFBundleURLSchemes"] == ["kudroid-jit-" + pairing_identifier.replace(".", "-").lower()]
        dex = (root / "framework/build/framework.dex").read_bytes()
        assert dex in main, "tested framework DEX missing"
        launcher = archive.read(parent + "StandaloneLauncher.bin")
        assert launcher == b"KUDLCH01" + main, "exported launcher does not match the current executable"
        return {"main_bundle": info["CFBundleIdentifier"], "helper_bundle": child["CFBundleIdentifier"],
                "main_minimum_ios": info["MinimumOSVersion"], "helper_minimum_ios": child["MinimumOSVersion"],
                "main_links_stikjit": False, "helper_links_stikjit": True,
                "framework_bundles_verified": len(frameworks),
                "pairing_metadata_bundle": pairing_identifier,
                "dex_sha256": hashlib.sha256(dex).hexdigest(), "ipa_sha256": hashlib.sha256(Path(ipa).read_bytes()).hexdigest()}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ipa", type=Path)
    parser.add_argument("--report", type=Path)
    parser.add_argument("--signing-bundle-id")
    args = parser.parse_args()
    result = verify(args.ipa, args.signing_bundle_id)
    if args.report: args.report.write_text(json.dumps(result, indent=2) + "\n")
    print("Verified JIT helper isolation, iOS gates, license/script resources and executable launcher.")
