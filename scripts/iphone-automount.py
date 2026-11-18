#!/usr/bin/env python3
"""Mount a shared Documents drive when a configured USB device connects."""

import argparse
import asyncio
from datetime import datetime
import importlib.util
import json
import logging
from logging.handlers import RotatingFileHandler
import msvcrt
import os
from pathlib import Path
import subprocess
import sys
import time
from urllib.request import Request, urlopen
from urllib.error import HTTPError
import winreg
import xml.etree.ElementTree as ET

import psutil
import win32wnet
from pymobiledevice3.usbmux import list_devices


ROOT = Path.home() / '.kudroid'
SCRIPT = Path(__file__).resolve()
CONFIG = ROOT / 'iphone-automount.json'
STATUS = ROOT / 'iphone-automount.status.json'
STOP = ROOT / 'iphone-automount.stop'
MOUNT_STATE = ROOT / 'iphone-explorer.json'
RUN_KEY = r'Software\Microsoft\Windows\CurrentVersion\Run'
RUN_NAME = 'KudroidDocuments'


def read_json(path):
    try:
        return json.loads(path.read_text(encoding='utf-8-sig'))
    except (OSError, ValueError):
        return None


def write_json(path, value):
    temporary = path.with_suffix('.tmp')
    temporary.write_text(json.dumps(value, indent=2), encoding='utf-8')
    temporary.replace(path)


def process_matches(pid, started, script):
    try:
        process = psutil.Process(int(pid))
        return abs(process.create_time() - started) < 0.01 and any(
            Path(argument).resolve() == script for argument in process.cmdline()[1:]
        )
    except (psutil.Error, ValueError, OSError):
        return False


def watcher_running():
    state = read_json(STATUS)
    return bool(state and process_matches(state['pid'], state['started'], SCRIPT))


def bridge_running(state, mount_script):
    try:
        started = datetime.fromisoformat(state['StartTime'].replace('Z', '+00:00')).timestamp()
        return process_matches(state['ProcessId'], started, mount_script.with_name('iphone-webdav.py'))
    except (KeyError, ValueError, TypeError):
        return False


def mapping_present(state):
    try:
        return win32wnet.WNetGetConnection(state['Drive'] + ':').casefold() == state['RemotePath'].casefold()
    except win32wnet.error:
        return False


def bridge_healthy(state):
    body = b'<propfind xmlns="DAV:"><prop><resourcetype/></prop></propfind>'
    try:
        request = Request(state['Url'], data=body, method='PROPFIND',
                          headers={'Depth': '0', 'Content-Type': 'application/xml'})
        with urlopen(request, timeout=5) as response:
            if response.status != 207:
                return False
            root = ET.fromstring(response.read(65536))
        for properties in root.findall('.//{DAV:}propstat'):
            status = properties.findtext('{DAV:}status', '')
            if ' 200 ' in status and properties.find('{DAV:}prop/{DAV:}resourcetype/{DAV:}collection') is not None:
                return True
    except HTTPError as error:
        error.close()
    except (OSError, ValueError, KeyError, ET.ParseError):
        pass
    return False


def same_options(state, config):
    return bool(state and state.get('Drive') == config['drive'] and
                state.get('BundleId') == config['bundle_id'] and
                state.get('Port') == config['port'] and
                bool(state.get('ReadOnly')) == config['readonly'])


def reconcile_action(config, serials, state, running, mapped):
    target = config.get('udid')
    serial = target if target in serials else None
    if not target and len(serials) == 1:
        serial = serials[0]
    compatible = same_options(state, config) and (
        not state.get('Udid') or state['Udid'] == (target or serial)
    )
    if not serial:
        if compatible and (target or not serials):
            return 'Unmount', None
        return None, None
    if state and not compatible:
        return None, None
    if running and mapped:
        return None, serial
    if state and running:
        return 'Unmount', serial
    return 'Mount', serial


async def usb_serials():
    devices = await asyncio.wait_for(list_devices(), 5)
    return [device.serial for device in devices if device.is_usb]


def run_mount(config, action, serial=None):
    specification = importlib.util.spec_from_file_location('bounded_command', SCRIPT.with_name('run-command.py'))
    runner = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(runner)
    command = ['powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass',
               '-File', config['mount_script'], '-Action', action, '-TimeoutSeconds', '45']
    if action == 'Mount':
        command += ['-Drive', config['drive'], '-BundleId', config['bundle_id'], '-Port', str(config['port'])]
        if serial:
            command += ['-Udid', serial]
        if config['readonly']:
            command += ['-ReadOnly']
    with (ROOT / 'iphone-automount.commands.log').open('a', encoding='utf-8') as output:
        return runner.run(command, 120, stdin=subprocess.DEVNULL, stdout=output,
                          stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW)


async def watch_loop(config):
    write_json(STATUS, {'pid': os.getpid(), 'started': psutil.Process().create_time()})
    logging.info('Watcher started; drive %s:', config['drive'])
    next_attempt = 0
    previous_error = None
    while not STOP.exists():
        try:
            serials = await usb_serials()
            previous_error = None
        except Exception as error:
            message = str(error)
            if message != previous_error:
                logging.warning('USB detection unavailable: %s', message)
                previous_error = message
            await asyncio.sleep(3)
            continue
        state = read_json(MOUNT_STATE)
        running = bool(state and bridge_running(state, Path(config['mount_script'])))
        mapped = bool(state and mapping_present(state))
        action, serial = reconcile_action(config, serials, state, running, mapped)
        if action is None and serial and running and mapped:
            if not await asyncio.to_thread(bridge_healthy, state):
                logging.warning('Documents bridge is unavailable; reconnecting the drive')
                action, serial = reconcile_action(config, serials, state, running, False)
        if action and time.monotonic() >= next_attempt:
            logging.info('%s requested', action)
            result = await asyncio.to_thread(run_mount, config, action, serial)
            if result:
                logging.warning('%s failed with exit code %s; retrying in 30 seconds', action, result)
                next_attempt = time.monotonic() + 30
            else:
                logging.info('%s completed', action)
                next_attempt = 0
        await asyncio.sleep(3)
    logging.info('Watcher stopped')


def stop_watcher():
    if not watcher_running():
        return
    STOP.touch()
    deadline = time.monotonic() + 150
    while watcher_running() and time.monotonic() < deadline:
        time.sleep(0.2)
    if watcher_running():
        raise RuntimeError('The watcher did not stop within its deadline')


def startup_command():
    return subprocess.list2cmdline([str(Path(sys.executable).with_name('pythonw.exe')), '-u', str(SCRIPT), 'watch'])


def install(args):
    serials = asyncio.run(usb_serials()) if not args.udid else []
    if not args.udid and len(serials) > 1:
        raise RuntimeError('More than one USB device is connected. Pass -Udid explicitly.')
    config = {
        'drive': args.drive.upper(), 'bundle_id': args.bundle_id, 'port': args.port,
        'readonly': args.readonly, 'udid': args.udid or (serials[0] if serials else None),
        'mount_script': str(SCRIPT.with_name('iphone-explorer.ps1')),
    }
    stop_watcher()
    STOP.unlink(missing_ok=True)
    write_json(CONFIG, config)
    with winreg.CreateKey(winreg.HKEY_CURRENT_USER, RUN_KEY) as key:
        winreg.SetValueEx(key, RUN_NAME, 0, winreg.REG_SZ, startup_command())
    with (ROOT / 'iphone-automount.launch.log').open('a', encoding='utf-8') as output:
        subprocess.Popen([str(Path(sys.executable).with_name('pythonw.exe')), '-u', str(SCRIPT), 'watch'],
                         stdin=subprocess.DEVNULL, stdout=output, stderr=output,
                         creationflags=subprocess.CREATE_NO_WINDOW)
    deadline = time.monotonic() + 15
    while not watcher_running() and time.monotonic() < deadline:
        time.sleep(0.2)
    if not watcher_running():
        raise RuntimeError('Watcher startup failed; check iphone-automount.launch.log')
    print(f'Automatic mounting enabled for {config["drive"]}: at Windows sign-in.')


def remove():
    with winreg.CreateKey(winreg.HKEY_CURRENT_USER, RUN_KEY) as key:
        try:
            saved, _ = winreg.QueryValueEx(key, RUN_NAME)
            if saved == startup_command():
                winreg.DeleteValue(key, RUN_NAME)
        except FileNotFoundError:
            pass
    stop_watcher()
    print('Automatic mounting disabled. The current drive can still be unmounted manually.')


def watch():
    with (ROOT / 'iphone-automount.lock').open('a+b') as lock:
        if lock.tell() == 0:
            lock.write(b'0')
            lock.flush()
        lock.seek(0)
        try:
            msvcrt.locking(lock.fileno(), msvcrt.LK_NBLCK, 1)
        except OSError:
            return
        config = read_json(CONFIG)
        if not config:
            raise RuntimeError('Automatic mounting configuration is missing')
        logging.basicConfig(level=logging.INFO, format='%(asctime)s %(levelname)s %(message)s', handlers=[
            RotatingFileHandler(ROOT / 'iphone-automount.log', maxBytes=1_000_000, backupCount=1, encoding='utf-8'),
        ])
        try:
            asyncio.run(watch_loop(config))
        finally:
            STATUS.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['install', 'remove', 'status', 'watch'])
    parser.add_argument('--drive', default='K')
    parser.add_argument('--bundle-id', default='com.kudroid.shell')
    parser.add_argument('--udid')
    parser.add_argument('--port', type=int, default=8765)
    parser.add_argument('--readonly', action='store_true')
    args = parser.parse_args()
    if len(args.drive) != 1 or not 'D' <= args.drive.upper() <= 'Z' or not 1024 <= args.port <= 65535:
        parser.error('Invalid drive or port')
    ROOT.mkdir(exist_ok=True)
    if args.action == 'install':
        install(args)
    elif args.action == 'remove':
        remove()
    elif args.action == 'status':
        with winreg.CreateKey(winreg.HKEY_CURRENT_USER, RUN_KEY) as key:
            try:
                registered = winreg.QueryValueEx(key, RUN_NAME)[0] == startup_command()
            except FileNotFoundError:
                registered = False
        print(json.dumps({'enabled_at_sign_in': registered, 'running': watcher_running(), 'config': read_json(CONFIG)}, indent=2))
    else:
        watch()


if __name__ == '__main__':
    main()
