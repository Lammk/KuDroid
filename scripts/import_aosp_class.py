#!/usr/bin/env python3
"""Copy framework sources, preserving licenses and removing hidden API annotations."""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
AOSP = os.path.join(ROOT, 'third_party', 'aosp', 'platform_frameworks_base')
ROOTS = ['core/java', 'graphics/java', 'media/java', 'location/java', 'opengl/java', 'sax/java']
DEST = os.path.join(ROOT, 'framework')
MODIFICATION_NOTICE = '// Modified: adapted for runtime compatibility.\n'

# Annotations that only exist for the platform build.
DROP = ['UnsupportedAppUsage', 'TestApi', 'SystemApi', 'RemotableViewMethod', 'InspectableProperty',
        'ViewDebug\\.ExportedProperty', 'ViewDebug\\.CapturedViewProperty', 'UnsupportedAppUsage',
        'ChangeId', 'EnabledAfter', 'Disabled', 'UiThread', 'MainThread', 'WorkerThread',
        'GuardedBy', 'TestApi', 'Retention', 'Target']


def clean(text):
    original = text
    for name in DROP:
        text = re.sub(r'[ \t]*@' + name + r'(\((?:[^()]|\([^()]*\))*\))?[ \t]*\n', '', text)
        text = re.sub(r'@' + name + r'(\((?:[^()]|\([^()]*\))*\))?[ \t]*', '', text)
    text = re.sub(r'(?m)^import android\.annotation\.(TestApi|SystemApi);\n', '', text)
    text = re.sub(r'(?m)^import android\.compat\.[\w.]+;\n', '', text)
    # Interpolators: drop the RenderThread-only native factory hooks.
    text = re.sub(r'(?m)^import com\.android\.internal\.view\.animation\.\w+;\n', '', text)
    text = re.sub(r'@HasNativeInterpolator\s*', '', text)
    text = re.sub(r'\s*implements NativeInterpolatorFactory', '', text)
    text = re.sub(r',\s*NativeInterpolatorFactory', '', text)
    text = re.sub(r'(?s)\s*/\*\* @hide \*/\s*@Override\s*public long createNativeInterpolator\(\)\s*\{.*?\n    \}\n',
                  '\n', text)
    text = re.sub(r'(?s)\s*@Override\s*public long createNativeInterpolator\(\)\s*\{.*?\n    \}\n', '\n', text)
    if text != original:
        header = re.match(r'\s*/\*.*?\*/', text, re.DOTALL)
        if header is None or 'Apache License' not in header.group():
            raise ValueError('Modified import is missing its Apache license header')
        if MODIFICATION_NOTICE.strip() not in text:
            end = header.end()
            text = text[:end] + '\n' + MODIFICATION_NOTICE + text[end:]
    return text


def main():
    for rel in sys.argv[1:]:
        for r in ROOTS:
            src = os.path.join(AOSP, r, rel)
            if os.path.exists(src):
                break
        else:
            print('not found:', rel, file=sys.stderr)
            continue
        dest = os.path.join(DEST, rel)
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        with open(src, encoding='utf-8') as f:
            text = clean(f.read())
        with open(dest, 'w', encoding='utf-8') as f:
            f.write(text)
        print('imported', rel)


if __name__ == '__main__':
    main()
