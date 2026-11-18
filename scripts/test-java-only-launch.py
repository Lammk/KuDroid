#!/usr/bin/env python3
"""Exercise the full launch path without a native-library directory."""
import argparse
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--build-dir', type=Path, required=True)
args = parser.parse_args()

def run(command, timeout=120):
    subprocess.run([str(p) for p in command], check=True, timeout=timeout)

with tempfile.TemporaryDirectory(prefix='kudroid-java-launch-') as temporary:
    directory = Path(temporary)
    classes = directory / 'classes'
    classes.mkdir()
    app = directory / 'android_root/data/app/launch.fixture'
    app.mkdir(parents=True)
    (app / 'AndroidManifest.xml').write_text('''<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="launch.fixture">
<application><activity android:name="launch.fixture.JavaOnlyLaunchActivity">
<intent-filter><action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.LAUNCHER"/></intent-filter>
</activity></application></manifest>''')
    run(['javac', '-source', '8', '-target', '8', '-nowarn', '-bootclasspath',
         root / 'framework/build/classes', '-d', classes, root / 'tests/java/JavaOnlyLaunchActivity.java'])
    d8 = root / 'third_party/d8/r8.jar'
    if not d8.exists():
        d8 = root / 'third_party/d8/d8.jar'
    run(['java', '-cp', d8, 'com.android.tools.r8.D8', '--min-api', '29',
         '--lib', root / 'framework/build/classes', '--output', app, *classes.rglob('*.class')])
    assert not (app / 'lib').exists()
    run([args.build_dir.resolve() / 'test_java_only_launch', directory], 30)
