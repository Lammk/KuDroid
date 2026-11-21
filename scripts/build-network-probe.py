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
parser.add_argument('--framework-classes', type=Path, default=root / 'framework/build/classes')
parser.add_argument('--lan-host')
parser.add_argument('--tcp-port', type=int, default=43210)
parser.add_argument('--udp-port', type=int, default=43211)
parser.add_argument('--token')
parser.add_argument('--broadcast-address', default='')
args = parser.parse_args()
if args.lan_host and (not args.token or not 1 <= args.tcp_port <= 65535 or not 1 <= args.udp_port <= 65535):
    parser.error('LAN mode requires a token and valid TCP/UDP ports')
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
if args.lan_host:
    assets = app / 'assets'
    assets.mkdir(exist_ok=True)
    (assets / 'lan-target.txt').write_text('\n'.join((args.lan_host, str(args.tcp_port), str(args.udp_port),
                                                   args.token, args.broadcast_address)) + '\n', encoding='utf-8')
elif (app / 'assets/lan-target.txt').exists():
    (app / 'assets/lan-target.txt').unlink()

def run(parts):
    subprocess.run([str(p) for p in parts], check=True, timeout=120)

run(['javac', '-source', '8', '-target', '8', '-nowarn', '-bootclasspath',
     args.framework_classes, '-d', classes,
     root / 'tools/network-probe/NetworkProbeActivity.java'])
d8 = root / 'third_party/d8/r8.jar'
if not d8.exists():
    d8 = root / 'third_party/d8/d8.jar'
run(['java', '-cp', d8, 'com.android.tools.r8.D8', '--min-api', '29',
     '--lib', args.framework_classes, '--output', app, *classes.rglob('*.class')])
with zipfile.ZipFile(app / 'base.apk', 'w', compression=zipfile.ZIP_DEFLATED) as apk:
    apk.write(app / 'AndroidManifest.xml', 'AndroidManifest.xml')
    apk.write(app / 'classes.dex', 'classes.dex')
    if args.lan_host:
        apk.write(app / 'assets/lan-target.txt', 'assets/lan-target.txt')
print(app)
