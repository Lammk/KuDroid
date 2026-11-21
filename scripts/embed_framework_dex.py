#!/usr/bin/env python3
"""Embed framework DEX bytes in a C++ header for startup."""
import pathlib
import shutil
import sys

root = pathlib.Path(__file__).resolve().parent.parent
dex = root / 'framework/build/framework.dex'
out = root / 'include/kudroid/framework_dex_bytes.h'

if not dex.is_file():
    sys.exit(f'ERROR: {dex} does not exist — run framework/build.sh first')

data = dex.read_bytes()
if data[:4] != b'dex\n':
    sys.exit(f'ERROR: {dex} is not a valid DEX file (magic = {data[:4]!r})')

lines = [
    '// Auto-generated from framework/build/framework.dex — DO NOT EDIT MANUALLY.',
    '// Regenerate: bash framework/build.sh',
    '// Mixed-license binary data; not licensed under MIT alone.',
    '// Component terms and corresponding-source requirements: NOTICE section 6.',
    '#pragma once',
    '#include <cstddef>',
    '#include <cstdint>',
    '',
    f'static const size_t g_framework_dex_size = {len(data)};',
    'static const uint8_t g_framework_dex_bytes[] = {',
]
for i in range(0, len(data), 12):
    lines.append('    ' + ', '.join(f'0x{b:02x}' for b in data[i:i + 12]) + ',')
lines.append('};')

out.parent.mkdir(parents=True, exist_ok=True)
out.write_text('\n'.join(lines) + '\n', encoding='utf-8')
licenses = root / 'ios-app/KuDroidShell/Resources/licenses/framework'
licenses.mkdir(parents=True, exist_ok=True)
for name in ('LICENSE', 'LICENSE-APACHE-2.0', 'LICENSE-GPLv2-CPE', 'NOTICE'):
    shutil.copyfile(root / name, licenses / name)
for name in ('harmony-NOTICE', 'aosp-libcore-NOTICE', 'provenance.json'):
    shutil.copyfile(root / 'framework/licenses' / name, licenses / name)
print(f'Generated {out} ({len(data)} bytes)')
