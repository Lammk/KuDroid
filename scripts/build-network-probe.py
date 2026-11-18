#!/usr/bin/env python3
"""Package a Java-only connectivity probe for the local runtime."""
import argparse
import json
from pathlib import Path
import subprocess
import zipfile

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
output = args.output.resolve()
output.mkdir(parents=True, exist_ok=True)
classes = output / 'classes'
classes.mkdir(exist_ok=True)
app = output / 'org.kudroid.networkprobe'
app.mkdir(exist_ok=True)
manifest = '''<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="org.kudroid.networkprobe" android:versionCode="1" android:versionName="1.0">
<uses-sdk android:minSdkVersion="14" android:targetSdkVersion="22"/>
<uses-permission android:name="android.permission.INTERNET"/>
<application android:label="Network Probe"><activity android:name="org.kudroid.networkprobe.NetworkProbeActivity" android:exported="true">
<intent-filter><action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.LAUNCHER"/></intent-filter>
</activity></application></manifest>'''
(app / 'AndroidManifest.xml').write_text(manifest, encoding='utf-8')
(app / 'app_info.json').write_text(json.dumps({'package': 'org.kudroid.networkprobe',
    'label': 'Network Probe', 'mainActivity': 'org.kudroid.networkprobe.NetworkProbeActivity',
    'isGame': False, 'permissions': ['android.permission.INTERNET']}), encoding='utf-8')

def run(parts):
    subprocess.run([str(p) for p in parts], check=True, timeout=120)

run(['javac', '-source', '8', '-target', '8', '-nowarn', '-bootclasspath',
     root / 'framework/build/classes', '-d', classes,
     root / 'tools/network-probe/NetworkProbeActivity.java'])
d8 = root / 'third_party/d8/r8.jar'
if not d8.exists():
    d8 = root / 'third_party/d8/d8.jar'
run(['java', '-cp', d8, 'com.android.tools.r8.D8', '--min-api', '29',
     '--lib', root / 'framework/build/classes', '--output', app, *classes.rglob('*.class')])
with zipfile.ZipFile(app / 'base.apk', 'w', compression=zipfile.ZIP_DEFLATED) as apk:
    apk.write(app / 'AndroidManifest.xml', 'AndroidManifest.xml')
    apk.write(app / 'classes.dex', 'classes.dex')
print(app)
