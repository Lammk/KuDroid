#!/usr/bin/env python3
"""Generate annotated reference-return adapters before DEX compilation."""
import argparse
import importlib.util
from pathlib import Path
import tempfile

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('framework_build', ROOT / 'framework/build.py')
build = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--classes', required=True, type=Path)
    args = parser.parse_args()
    classes = args.classes.resolve()
    if not classes.is_relative_to((ROOT / 'framework/build').resolve()) or not classes.is_dir():
        parser.error('Expected the framework classes directory')
    export = 'java.base/jdk.internal.org.objectweb.asm=ALL-UNNAMED'
    with tempfile.TemporaryDirectory(prefix='return-bridges-') as directory:
        build.run([build.java_tool('javac'), '--add-exports', export, '-d', directory,
                   ROOT / 'scripts/ReturnTypeBridges.java'], 60)
        build.run([build.java_tool('java'), '--add-exports', export, '-cp', directory,
                   'ReturnTypeBridges', classes], 60)

if __name__ == '__main__':
    main()
