#!/usr/bin/env python3
"""Compile the framework DEX on Windows or POSIX using the pinned compiler."""

import argparse
import importlib.util
import locale
import os
from pathlib import Path
import shutil
import sys
import zipfile


ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("deadline", ROOT / "scripts/run-command.py")
deadline = importlib.util.module_from_spec(spec)
spec.loader.exec_module(deadline)


def run(command, seconds):
    code = deadline.run([str(p) for p in command], seconds, cwd=ROOT)
    if code:
        raise SystemExit(code)


def java_tool(name):
    suffix = ".exe" if os.name == "nt" else ""
    if os.environ.get("JAVA_HOME"):
        candidate = Path(os.environ["JAVA_HOME"]) / "bin" / (name + suffix)
        if candidate.is_file():
            return str(candidate)
    tool = shutil.which(name)
    if not tool:
        raise SystemExit(f"{name} not found. Install JDK 17 or set JAVA_HOME.")
    return tool


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--no-embed", action="store_true")
    parser.add_argument("--require-d8", action="store_true")
    parser.add_argument("--timeout", type=int, default=240)
    args = parser.parse_args()
    if args.timeout <= 0:
        parser.error("Timeout must be positive")
    javac, java = java_tool("javac"), java_tool("java")
    explicit = os.environ.get("KUDROID_D8_JAR")
    candidates = ([Path(explicit)] if explicit else []) + [ROOT / "third_party/d8/d8.jar", ROOT / "third_party/d8/r8.jar"]
    d8 = next((p.resolve() for p in candidates if p.is_file()), None)
    if d8 is None:
        if args.require_d8 or not (ROOT / "include/kudroid/framework_dex_bytes.h").is_file():
            raise SystemExit("Pinned D8 missing: place d8.jar or r8.jar in third_party/d8.")
        print("Pinned D8 missing; keeping the existing embedded framework.")
        return
    framework = ROOT / "framework"
    build = framework / "build"
    classes = build / "classes"
    if build.is_symlink() or build.resolve().parent != framework.resolve():
        raise SystemExit("Unsafe framework build directory")
    sources = sorted(p for p in framework.rglob("*.java") if not p.is_relative_to(build))
    if not sources:
        raise SystemExit("No framework Java sources found")
    # Keep the existing DEX until both compilers succeed.
    if classes.exists():
        if classes.is_symlink() or classes.resolve().parent != build.resolve():
            raise SystemExit("Unsafe framework classes directory")
        shutil.rmtree(classes)
    classes.mkdir(parents=True)
    boot = build / "empty-bootclasspath"
    boot.mkdir(exist_ok=True)
    arguments = ["-encoding", "UTF-8", "-nowarn", "-source", "8", "-target", "8",
                 "-bootclasspath", boot, "-d", classes, *sources]
    argfile = build / "javac.args"
    lines = ['"' + str(p).replace("\\", "/").replace('"', '\\"') + '"' for p in arguments]
    argfile.write_text("\n".join(lines) + "\n", encoding=locale.getpreferredencoding(False))
    run([javac, "@" + str(argfile)], args.timeout)
    run([sys.executable, ROOT / 'scripts/fetch-legacy-http.py', '--classes', classes], 60)
    run([sys.executable, ROOT / 'scripts/framework-return-bridges.py', '--classes', classes], 120)
    jar = build / "framework-classes.jar"
    with zipfile.ZipFile(jar, "w", zipfile.ZIP_STORED) as archive:
        for path in sorted(classes.rglob("*.class")):
            archive.write(path, path.relative_to(classes).as_posix())
    kotlin = [ROOT / "third_party/kotlin" / name for name in
              ("kotlin-stdlib-1.9.24.jar", "kotlinx-coroutines-core-jvm-1.8.0.jar")]
    staging = build / "dex-output"
    if staging.is_symlink() or staging.resolve().parent != build.resolve():
        raise SystemExit("Unsafe DEX output directory")
    if staging.exists():
        shutil.rmtree(staging)
    staging.mkdir()
    run([java, "-cp", d8, "com.android.tools.r8.D8", "--min-api", "29", "--output", staging,
         jar, *[p for p in kotlin if p.is_file()]], args.timeout)
    dex = staging / "classes.dex"
    if not dex.is_file() or dex.read_bytes()[:4] != b"dex\n":
        raise SystemExit("D8 did not produce a valid classes.dex")
    if list(staging.glob("classes[2-9]*.dex")):
        raise SystemExit("Framework output contains multiple DEX files")
    dex.replace(build / "framework.dex")
    if not args.no_embed:
        run([sys.executable, ROOT / "scripts/embed_framework_dex.py"], args.timeout)
    print(f"Framework DEX: {build / 'framework.dex'}")


if __name__ == "__main__":
    main()
