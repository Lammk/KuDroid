#!/usr/bin/env python3
"""Check connection transitions and drive ownership for automatic mounting."""

import asyncio
import importlib.util
from pathlib import Path
import tempfile
from http.server import BaseHTTPRequestHandler, HTTPServer
import threading
import unittest
from unittest.mock import AsyncMock, patch


specification = importlib.util.spec_from_file_location('automount', Path(__file__).with_name('iphone-automount.py'))
automount = importlib.util.module_from_spec(specification)
specification.loader.exec_module(automount)


class MountTransitions(unittest.TestCase):
    def setUp(self):
        self.config = {'drive': 'K', 'bundle_id': 'example.shell', 'port': 8765,
                       'readonly': False, 'udid': 'target', 'mount_script': str(Path(__file__).with_name('iphone-explorer.ps1'))}
        self.state = {'Drive': 'K', 'BundleId': 'example.shell', 'Port': 8765,
                      'ReadOnly': False, 'Udid': 'target'}

    def action(self, serials, state, running=False, mapped=False):
        return automount.reconcile_action(self.config, serials, state, running, mapped)

    def test_connect_mounts_and_idle_does_not_remount(self):
        self.assertEqual(self.action(['target'], None), ('Mount', 'target'))
        self.assertEqual(self.action(['target'], self.state, True, True), (None, 'target'))

    def test_disconnect_removes_own_mapping(self):
        self.assertEqual(self.action([], self.state, True, True), ('Unmount', None))
        self.assertEqual(self.action(['other'], self.state, True, True), ('Unmount', None))
        self.assertEqual(self.action([], None), (None, None))

    def test_dead_bridge_recovers_and_missing_mapping_restarts(self):
        self.assertEqual(self.action(['target'], self.state, False, True), ('Mount', 'target'))
        self.assertEqual(self.action(['target'], self.state, True, False), ('Unmount', 'target'))

    def test_unrelated_drives_and_devices_are_preserved(self):
        for change in [{'Drive': 'L'}, {'Udid': 'other'}, {'BundleId': 'other.shell'}, {'ReadOnly': True}]:
            state = dict(self.state, **change)
            self.assertEqual(self.action([], state, True, True), (None, None))
            self.assertEqual(self.action(['target'], state, True, True), (None, None))

    def test_existing_unpinned_mapping_is_reused(self):
        state = dict(self.state, Udid='')
        self.assertEqual(self.action(['target'], state, True, True), (None, 'target'))

    def test_unconfigured_multiple_devices_are_not_selected(self):
        self.config['udid'] = None
        self.assertEqual(self.action(['first', 'second'], None), (None, None))
        self.assertEqual(self.action(['first'], None), ('Mount', 'first'))

    def test_usb_query_failure_does_not_unmount(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            stop = root / 'stop'

            async def unavailable():
                stop.touch()
                raise OSError('USB service temporarily unavailable')

            with patch.object(automount, 'STATUS', root / 'status.json'), \
                 patch.object(automount, 'STOP', stop), \
                 patch.object(automount, 'usb_serials', unavailable), \
                 patch.object(automount, 'run_mount') as command, \
                 patch.object(automount.asyncio, 'sleep', AsyncMock()):
                asyncio.run(automount.watch_loop(self.config))
                command.assert_not_called()


    def test_live_but_stale_bridge_is_unmounted(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            stop = root / 'stop'
            def unmount(config, action, serial):
                stop.touch()
                self.assertEqual((action, serial), ('Unmount', 'target'))
                return 0
            with patch.object(automount, 'STATUS', root / 'status.json'), \
                 patch.object(automount, 'STOP', stop), \
                 patch.object(automount, 'usb_serials', AsyncMock(return_value=['target'])), \
                 patch.object(automount, 'read_json', return_value=self.state), \
                 patch.object(automount, 'bridge_running', return_value=True), \
                 patch.object(automount, 'mapping_present', return_value=True), \
                 patch.object(automount, 'bridge_healthy', return_value=False), \
                 patch.object(automount, 'run_mount', side_effect=unmount) as command, \
                 patch.object(automount.asyncio, 'sleep', AsyncMock()):
                asyncio.run(automount.watch_loop(self.config))
                command.assert_called_once()


class BridgeHealth(unittest.TestCase):
    def query(self, status, body):
        class Handler(BaseHTTPRequestHandler):
            def do_PROPFIND(handler):
                self.assertEqual(handler.headers['Depth'], '0')
                request = handler.rfile.read(int(handler.headers['Content-Length']))
                self.assertIn(b'resourcetype', request)
                handler.send_response(status)
                handler.end_headers()
                handler.wfile.write(body)
            def log_message(handler, *args):
                pass
        with HTTPServer(('127.0.0.1', 0), Handler) as server:
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            try:
                return automount.bridge_healthy({'Url': f'http://127.0.0.1:{server.server_port}/'})
            finally:
                server.shutdown()
                thread.join(5)

    def test_accessible_documents_collection(self):
        self.assertTrue(self.query(207, b'<multistatus xmlns="DAV:"><response><propstat>'
            b'<prop><resourcetype><collection/></resourcetype></prop>'
            b'<status>HTTP/1.1 200 OK</status></propstat></response></multistatus>'))

    def test_missing_container(self):
        self.assertFalse(self.query(404, b''))

    def test_multistatus_with_missing_root(self):
        self.assertFalse(self.query(207, b'<multistatus xmlns="DAV:"><response><propstat>'
            b'<prop><resourcetype><collection/></resourcetype></prop>'
            b'<status>HTTP/1.1 404 Not Found</status></propstat></response></multistatus>'))

    def test_invalid_response(self):
        self.assertFalse(self.query(207, b'invalid XML'))


if __name__ == '__main__':
    unittest.main()
