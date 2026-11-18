#!/usr/bin/env python3
"""Run native callback dispatch and VM-lock regression checks."""

import argparse
from pathlib import Path
import subprocess
import tempfile


def run(command, seconds=120):
    subprocess.run([str(value) for value in command], check=True, timeout=seconds)


def main():
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build-dir', type=Path, default=root / 'build-host-tls')
    parser.add_argument('--skip-build', action='store_true')
    args = parser.parse_args()
    if not args.skip_build:
        run(['cmake', '-S', root, '-B', args.build_dir, '-G', 'Ninja', '-DKUDROID_BUILD_HOST_TESTS=OFF'])
        run(['cmake', '--build', args.build_dir, '--target', 'test_native_callbacks', '-j6'], 240)
    with tempfile.TemporaryDirectory(prefix='kudroid-native-callbacks-') as temporary:
        directory = Path(temporary)
        classes = directory / 'classes'
        classes.mkdir()
        run(['javac', '-source', '8', '-target', '8', '-nowarn', '-bootclasspath',
             root / 'framework/build/classes', '-d', classes, root / 'tests/java/NativeCallbackTests.java'])
        d8 = root / 'third_party/d8/r8.jar'
        if not d8.is_file():
            d8 = root / 'third_party/d8/d8.jar'
        run(['java', '-cp', d8, 'com.android.tools.r8.D8', '--min-api', '29', '--lib',
             root / 'framework/build/classes', '--output', directory, *classes.glob('*.class')])
        run([args.build_dir / 'test_native_callbacks', root / 'framework/build/framework.dex', directory / 'classes.dex'], 20)


if __name__ == '__main__':
    main()
