#!/usr/bin/env python3
"""Verify imported source notices and their binary/source distribution artifacts."""

import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import zipfile


ROOT = Path(__file__).resolve().parents[1]
LICENSE_HASHES = {
    'LICENSE-APACHE-2.0': 'cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30',
    'LICENSE-GPLv2-CPE': '4b9abebc4338048a7c2dc184e9f800deb349366bdf28eb23c2677a77b4c87726',
}
RESOURCE_SOURCES = {
    **{name: name for name in ('LICENSE', 'LICENSE-APACHE-2.0', 'LICENSE-GPLv2-CPE', 'NOTICE')},
    **{name: 'framework/licenses/' + name for name in ('harmony-NOTICE', 'aosp-libcore-NOTICE', 'provenance.json')},
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def source_header(text):
    match = re.match(r'\s*/\*.*?\*/', text, re.DOTALL)
    return match.group() if match else ''


def verify_sources(root=ROOT):
    inventory = json.loads((root / 'framework/licenses/provenance.json').read_text(encoding='utf-8'))
    entries = inventory['entries']
    paths = {entry['path'] for entry in entries}
    require(len(paths) == len(entries), 'Duplicate provenance entry')
    covered = {'include/jni.h', 'include/jni_md.h'}
    for path in (root / 'framework').rglob('*.java'):
        if 'build' in path.relative_to(root).parts:
            continue
        header = source_header(path.read_text(encoding='utf-8'))
        if 'apache.org/licenses/LICENSE-2.0' in header or 'GNU General Public License' in header:
            covered.add(path.relative_to(root).as_posix())
    require(paths == covered, 'Imported source inventory does not match covered files')
    for entry in entries:
        path = root / entry['path']
        text = path.read_text(encoding='utf-8')
        header = source_header(text)
        require(hashlib.sha256(header.encode()).hexdigest() == entry['retained_header_sha256'],
                'Retained license header changed: ' + entry['path'])
        expected = 'Apache-2.0' if 'apache.org/licenses/LICENSE-2.0' in header else 'GPL-2.0-only WITH Classpath-exception-2.0'
        require(entry['license'] == expected, 'Source license classification mismatch: ' + entry['path'])
        require(expected == 'Apache-2.0' or 'Classpath' in header,
                'Covered GPL source lacks the exception: ' + entry['path'])
        if entry['modified']:
            notice = text[len(header):len(header) + 220]
            require('// Modified' in notice, 'Missing prominent modification notice: ' + entry['path'])
            if expected.startswith('GPL'):
                require(re.search(r'Modified on \d{4}-\d{2}-\d{2}', notice),
                        'Modified GPL source lacks a dated notice: ' + entry['path'])
        for source in entry['sources']:
            require(source['url'].startswith('https://') and re.fullmatch('[0-9a-f]{64}', source['sha256']),
                    'Invalid upstream reference: ' + entry['path'])
    for name, digest in LICENSE_HASHES.items():
        require(hashlib.sha256((root / name).read_bytes().replace(b'\r\n', b'\n')).hexdigest() == digest,
                'Full license text differs from the verified upstream copy: ' + name)
    for name, source in RESOURCE_SOURCES.items():
        require((root / 'ios-app/KuDroidShell/Resources/licenses/framework' / name).read_bytes() == (root / source).read_bytes(),
                'Packaged source resource is stale: ' + name)
    native = root / 'ios-app/KuDroidShell/Resources/licenses/native'
    for component in json.loads((native / 'manifest.json').read_text(encoding='utf-8'))['components']:
        require(hashlib.sha256((native / component['file']).read_bytes().replace(b'\r\n', b'\n')).hexdigest() == component['sha256'],
                'Native license text is stale: ' + component['file'])
    return inventory


def verify_archive(path, root=ROOT):
    with zipfile.ZipFile(path) as archive:
        require(archive.testzip() is None, 'Source archive is corrupt')
        manifest = json.loads(archive.read('SOURCE-MANIFEST.json'))
        dex = (root / 'framework/build/framework.dex').read_bytes()
        require(manifest['dex_sha256'] == hashlib.sha256(dex).hexdigest(), 'Source archive DEX identity is stale')
        required = {p.relative_to(root).as_posix() for p in (root / 'framework').rglob('*.java')
                    if 'build' not in p.relative_to(root).parts}
        required.update(RESOURCE_SOURCES.values())
        required.update({'include/jni.h', 'include/jni_md.h', 'framework/build.py',
                         'framework/build.sh', 'scripts/embed_framework_dex.py',
                         'scripts/framework-return-bridges.py', 'scripts/ReturnTypeBridges.java',
                         'CMakeLists.txt', 'src/ios-pairing/rust-toolchain.toml'})
        native = root / 'ios-app/KuDroidShell/Resources/licenses/native'
        required.update(p.relative_to(root).as_posix() for p in native.iterdir() if p.is_file())
        require(required.issubset(manifest['sources']), 'Corresponding-source archive is incomplete')
        for name, digest in manifest['sources'].items():
            data = archive.read(name)
            require(hashlib.sha256(data).hexdigest() == digest, 'Source archive hash mismatch: ' + name)
            expected = (root / name).read_bytes()
            require(data == expected if name.endswith('.png') else
                    data.replace(b'\r\n', b'\n') == expected.replace(b'\r\n', b'\n'),
                    'Source archive does not match the build checkout: ' + name)


def verify_ipa(path, root=ROOT):
    with zipfile.ZipFile(path) as archive:
        require(archive.testzip() is None, 'IPA is corrupt')
        names = archive.namelist()
        plists = [name for name in names if name.startswith('Payload/') and name.count('/') == 2 and name.endswith('/Info.plist')]
        require(len(plists) == 1, 'IPA must contain one main app')
        parent = plists[0][:-len('Info.plist')]
        info = plistlib.loads(archive.read(plists[0]))
        binary = archive.read(parent + info['CFBundleExecutable'])
        dex = (root / 'framework/build/framework.dex').read_bytes()
        require(dex in binary, 'IPA does not contain the verified framework DEX')
        for name, source in RESOURCE_SOURCES.items():
            matches = [p for p in names if p.startswith(parent) and p.endswith('/licenses/framework/' + name)]
            require(len(matches) == 1, 'IPA license resource missing or ambiguous: ' + name)
            require(archive.read(matches[0]) == (root / source).read_bytes(), 'IPA license resource differs from source: ' + name)
        native = root / 'ios-app/KuDroidShell/Resources/licenses/native'
        for source in native.iterdir():
            matches = [p for p in names if p.startswith(parent) and p.endswith('/licenses/native/' + source.name)]
            require(len(matches) == 1, 'IPA native license resource missing or ambiguous: ' + source.name)
            require(archive.read(matches[0]) == source.read_bytes(), 'IPA native license resource differs from source: ' + source.name)
        matches = [p for p in names if p.startswith(parent) and p.endswith('/THIRD_PARTY_NOTICES.txt')]
        require(len(matches) == 1, 'IPA third-party notice resource missing or ambiguous')
        require(archive.read(matches[0]) == (root / 'ios-app/KuDroidShell/THIRD_PARTY_NOTICES.txt').read_bytes(),
                'IPA third-party notice resource is stale')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ipa', type=Path)
    parser.add_argument('--source-archive', type=Path)
    args = parser.parse_args()
    if args.ipa and not args.source_archive:
        parser.error('--ipa requires its matching --source-archive')
    inventory = verify_sources()
    if args.source_archive:
        verify_archive(args.source_archive)
    if args.ipa:
        verify_ipa(args.ipa)
    print(f"Verified {len(inventory['entries'])} imported source notices and requested distribution artifacts.")


if __name__ == '__main__':
    main()
