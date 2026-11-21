#!/usr/bin/env python3
"""Package the embedded framework sources and compilation scripts for distribution."""

import argparse
import hashlib
import json
from pathlib import Path
import tempfile
import zipfile


ROOT = Path(__file__).resolve().parents[1]


def package(output):
    paths = set()
    for directory in ('framework', 'scripts', 'src', 'include', 'cmake', 'ios-app'):
        for path in (ROOT / directory).rglob('*'):
            relative = path.relative_to(ROOT)
            if any(part in ('build', '__pycache__', 'target', '.build', 'libs', 'xtool') for part in relative.parts):
                continue
            if relative.as_posix() == 'include/kudroid/framework_dex_bytes.h':
                continue
            if path.is_file() and (path.suffix in ('.java', '.py', '.sh', '.json', '.patch', '.cpp', '.h', '.inc',
                                                   '.mm', '.swift', '.c', '.S', '.cmake', '.toml', '.lock', '.rs', '.plist', '.yml')
                                   or
                                   (path.name.endswith(('LICENSE', 'NOTICE')) or path.suffix == '.md'
                                    or path.name == 'UNICODE_LICENSE.txt') or
                                   path.parent == ROOT / 'ios-app/KuDroidShell/Resources/licenses/native'):
                paths.add(path)
    for name in ('LICENSE', 'LICENSE-APACHE-2.0', 'LICENSE-GPLv2-CPE', 'NOTICE',
                 'docs/licensing.md', 'include/jni.h', 'include/jni_md.h', 'CMakeLists.txt', 'README.md', 'icon.png'):
        paths.add(ROOT / name)
    dex = ROOT / 'framework/build/framework.dex'
    if not dex.is_file() or dex.read_bytes()[:4] != b'dex\n':
        raise ValueError('Build the framework DEX before packaging corresponding source')
    output = output.resolve()
    if output in paths:
        raise ValueError('Archive output would overwrite a source file')
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='framework-source-', dir=output.parent) as temporary:
        archive_path = Path(temporary) / 'source.zip'
        manifest = {'dex_sha256': hashlib.sha256(dex.read_bytes()).hexdigest(), 'sources': {}}
        with zipfile.ZipFile(archive_path, 'w', zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
            for path in sorted(paths):
                if not path.resolve().is_relative_to(ROOT):
                    raise ValueError('Source path is outside the checkout')
                data = path.read_bytes()
                name = path.relative_to(ROOT).as_posix()
                manifest['sources'][name] = hashlib.sha256(data).hexdigest()
                entry = zipfile.ZipInfo(name)
                entry.compress_type = zipfile.ZIP_DEFLATED
                entry.external_attr = (0o100755 if path.suffix == '.sh' else 0o100644) << 16
                archive.writestr(entry, data)
            archive.writestr('SOURCE-MANIFEST.json', json.dumps(manifest, indent=2) + '\n')
        archive_path.replace(output)
    print(f'Packaged framework source: {output}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    package(args.output)
