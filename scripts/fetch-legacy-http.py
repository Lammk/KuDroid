#!/usr/bin/env python3
"""Fetch and verify the pinned legacy HTTP library."""
import argparse
import hashlib
from pathlib import Path
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
LIBRARIES = [
    ('org/apache/httpcomponents/httpclient/4.3.5/httpclient-4.3.5.jar',
     'b184521bce85de3f7f57a9d6afba133b323c8752857723031ec5468d4feef8c6'),
    ('org/apache/httpcomponents/httpcore/4.3.2/httpcore-4.3.2.jar',
     'abd02320e2356f89d054dae4cf02306bef20a9cf7865b3ac94ec7552b4f1528b'),
    ('commons-codec/commons-codec/1.6/commons-codec-1.6.jar',
     '54b34e941b8e1414bd3e40d736efd3481772dc26db3296f6aa45cec9f6203d86'),
    ('commons-logging/commons-logging/1.1.3/commons-logging-1.1.3.jar',
     '70903f6fc82e9908c8da9f20443f61d90f0870a312642991fe8462a0b9391784'),
]

def library(relative, checksum):
    path = ROOT / 'third_party/apache-http-legacy' / Path(relative).name
    if not path.is_file():
        url = 'https://repo.maven.apache.org/maven2/' + relative
        with urllib.request.urlopen(url, timeout=30) as response:
            data = response.read(2 * 1024 * 1024)
        if hashlib.sha256(data).hexdigest() != checksum:
            raise RuntimeError('Legacy HTTP download checksum mismatch')
        path.parent.mkdir(parents=True, exist_ok=True)
        temporary = path.with_suffix('.download')
        temporary.write_bytes(data)
        temporary.replace(path)
    if hashlib.sha256(path.read_bytes()).hexdigest() != checksum:
        raise RuntimeError('Legacy HTTP library checksum mismatch')
    return path

def unpack(classes):
    classes = Path(classes).resolve()
    for relative, checksum in LIBRARIES:
        with zipfile.ZipFile(library(relative, checksum)) as archive:
            for name in archive.namelist():
                if not name.startswith('org/apache/') or not name.endswith('.class'):
                    continue
                target = (classes / name).resolve()
                if not target.is_relative_to(classes):
                    raise RuntimeError('Invalid legacy library class path')
                if target.is_file():
                    continue
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(archive.read(name))

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--classes', type=Path)
    args = parser.parse_args()
    if args.classes:
        unpack(args.classes)
    else:
        for relative, checksum in LIBRARIES:
            print(library(relative, checksum))
