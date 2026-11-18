#!/usr/bin/env python3
"""Check stale relay detection and bounded USB discovery."""

import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location("workflow", Path(__file__).with_name("windows-workflow.py"))
workflow = importlib.util.module_from_spec(spec)
spec.loader.exec_module(workflow)


class RelayChecks(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.directory = Path(temporary.name)
        (self.directory / ".kudroid").mkdir()
        self.relay = self.directory / ".kudroid/usbmux-relay.json"
        self.args = SimpleNamespace(action="ios", run=True, distribution="Ubuntu-26.04")
        self.configuration = {"Distribution": self.args.distribution,
                              "Address": "192.0.2.1:27015", "GuestAddress": "192.0.2.2"}
        home = patch.object(workflow.Path, "home", return_value=self.directory)
        home.start()
        self.addCleanup(home.stop)
        network = patch.object(workflow, "output", side_effect=[
            json.dumps([{"gateway": "192.0.2.1"}]), "192.0.2.2 "])
        self.network = network.start()
        self.addCleanup(network.stop)

    def save(self):
        self.relay.write_text(json.dumps(self.configuration), encoding="utf-8-sig")

    def test_current_relay(self):
        self.save()
        self.assertEqual(workflow.relay_address(self.args, ["wsl.exe"]), "192.0.2.1:27015")

    def test_changed_gateway(self):
        self.configuration["Address"] = "192.0.2.10:27015"
        self.save()
        with self.assertRaisesRegex(workflow.USBConnectionError, r"stale.*Administrator PowerShell.*connect-iphone"):
            workflow.relay_address(self.args, ["wsl.exe"])

    def test_changed_guest_with_same_gateway(self):
        self.configuration["GuestAddress"] = "192.0.2.3"
        self.save()
        with self.assertRaisesRegex(workflow.USBConnectionError, "stale"):
            workflow.relay_address(self.args, ["wsl.exe"])

    def test_legacy_configuration(self):
        del self.configuration["GuestAddress"]
        self.save()
        self.assertEqual(workflow.relay_address(self.args, ["wsl.exe"]), "192.0.2.1:27015")

    def test_build_without_run_does_not_check_network(self):
        self.args.run = False
        self.configuration["Address"] = "192.0.2.10:27015"
        self.save()
        self.assertEqual(workflow.relay_address(self.args, ["wsl.exe"]), "192.0.2.10:27015")
        self.network.assert_not_called()

    def test_other_distribution_ignores_relay(self):
        self.args.distribution = "Other"
        self.save()
        self.assertIsNone(workflow.relay_address(self.args, ["wsl.exe"]))
        self.network.assert_not_called()

    def test_no_saved_relay(self):
        self.assertIsNone(workflow.relay_address(self.args, ["wsl.exe"]))
        self.network.assert_not_called()


class DiscoveryChecks(unittest.TestCase):
    def discover(self, payload, status=0):
        def command(parts, seconds, **kwargs):
            self.assertEqual(parts, ["xtool", "devices", "--usb", "--no-wait"])
            self.assertEqual(seconds, 30)
            kwargs["stdout"].write(payload)
            if status:
                raise subprocess.CalledProcessError(status, parts)
        with patch.object(workflow, "require"), patch.object(workflow, "command", side_effect=command):
            workflow.check_usb_device()

    def test_connected_device(self):
        self.discover(b"Connected USB device\n")

    def test_no_device(self):
        with self.assertRaisesRegex(workflow.USBConnectionError, "No USB device connected"):
            self.discover(b"\n")

    def test_relay_failure_includes_diagnostic(self):
        with self.assertRaisesRegex(workflow.USBConnectionError, r"Operation now in progress.*Administrator PowerShell"):
            self.discover(b"Error: Operation now in progress", 1)

    def test_discovery_timeout(self):
        with self.assertRaisesRegex(workflow.USBConnectionError, "timeout"):
            self.discover(b"Command stopped after timeout or interruption (30s)", 124)


class RecoveryChecks(unittest.TestCase):
    def setUp(self):
        self.args = SimpleNamespace(action="ios", run=True, distribution="Ubuntu-26.04",
                                    toolchain_timeout=3600, build_timeout=240, test_timeout=120)
        self.options = ["ios", "--run", "--configuration", "release", "--clean"]
        relay = patch.object(workflow, "relay_address", return_value="192.0.2.1:27015")
        self.relay = relay.start()
        self.addCleanup(relay.stop)
        repair = patch.object(workflow, "repair_usb_relay")
        self.repair = repair.start()
        self.addCleanup(repair.stop)
        run = patch.object(workflow.subprocess, "run", return_value=SimpleNamespace(returncode=0))
        self.run = run.start()
        self.addCleanup(run.stop)

    def forward(self):
        return workflow.forward_workflow(self.args, ["wsl.exe"], "/source", self.options)

    def test_healthy_connection_does_not_elevate(self):
        self.assertEqual(self.forward(), 0)
        self.repair.assert_not_called()
        self.run.assert_called_once()

    def test_stale_relay_repairs_before_build_and_preserves_clean(self):
        self.relay.side_effect = [workflow.USBConnectionError("stale relay"), "192.0.2.1:27015"]
        self.assertEqual(self.forward(), 0)
        self.repair.assert_called_once_with(self.args.distribution)
        self.run.assert_called_once()
        self.assertIn("--clean", self.run.call_args.args[0])

    def test_discovery_failure_repairs_and_reloads_address(self):
        self.relay.side_effect = ["192.0.2.1:27015", "192.0.2.10:27015"]
        self.run.side_effect = [SimpleNamespace(returncode=75), SimpleNamespace(returncode=0)]
        self.assertEqual(self.forward(), 0)
        self.repair.assert_called_once_with(self.args.distribution)
        first, second = [call.args[0] for call in self.run.call_args_list]
        self.assertIn("--clean", first)
        self.assertIn("--clean", second)
        self.assertIn("release", second)
        self.assertEqual(second[-2:], ["--usbmux-address", "192.0.2.10:27015"])
        self.assertIn("--clean", self.options)

    def test_deployment_failure_reuses_build_after_clean(self):
        self.run.side_effect = [SimpleNamespace(returncode=76), SimpleNamespace(returncode=0)]
        self.assertEqual(self.forward(), 0)
        self.repair.assert_called_once()
        first, second = [call.args[0] for call in self.run.call_args_list]
        self.assertIn("--clean", first)
        self.assertNotIn("--clean", second)

    def test_persistent_usb_failure_retries_once(self):
        self.run.return_value = SimpleNamespace(returncode=75)
        self.assertEqual(self.forward(), 75)
        self.assertEqual(self.run.call_count, 2)
        self.repair.assert_called_once()

    def test_persistent_stale_relay_stops(self):
        self.relay.side_effect = workflow.USBConnectionError("stale relay")
        with self.assertRaises(workflow.USBConnectionError):
            self.forward()
        self.repair.assert_called_once()
        self.run.assert_not_called()

    def test_build_failure_does_not_elevate(self):
        self.run.return_value = SimpleNamespace(returncode=1)
        self.assertEqual(self.forward(), 1)
        self.repair.assert_not_called()
        self.run.assert_called_once()

    def test_build_without_run_does_not_repair(self):
        self.args.run = False
        self.run.return_value = SimpleNamespace(returncode=75)
        self.assertEqual(self.forward(), 75)
        self.repair.assert_not_called()
        self.run.assert_called_once()

    def test_failed_or_cancelled_repair_stops(self):
        self.relay.side_effect = workflow.USBConnectionError("stale relay")
        self.repair.side_effect = subprocess.CalledProcessError(1, ["powershell.exe"])
        with self.assertRaises(subprocess.CalledProcessError):
            self.forward()
        self.repair.assert_called_once()
        self.run.assert_not_called()


class DeploymentChecks(unittest.TestCase):
    def test_failed_deployment_with_working_usb_preserves_error(self):
        failure = subprocess.CalledProcessError(1, ["xtool"])
        with patch.object(workflow, "command", side_effect=failure), patch.object(workflow, "check_usb_device"):
            with self.assertRaises(subprocess.CalledProcessError) as caught:
                workflow.run_ios_app(Path("app"), "debug", 120)
        self.assertIs(caught.exception, failure)

    def test_failed_deployment_with_broken_usb_requests_repair(self):
        failure = subprocess.CalledProcessError(1, ["xtool"])
        with patch.object(workflow, "command", side_effect=failure), patch.object(
                workflow, "check_usb_device", side_effect=workflow.USBConnectionError("connection failed")):
            with self.assertRaises(workflow.USBDeploymentError):
                workflow.run_ios_app(Path("app"), "debug", 120)

    def test_successful_deployment_does_not_probe_again(self):
        with patch.object(workflow, "command") as command, patch.object(workflow, "check_usb_device") as discovery:
            workflow.run_ios_app(Path("app"), "release", 240)
            command.assert_called_once_with(["xtool", "dev", "run", "--usb", "-c", "release"],
                                            240, cwd=Path("app"))
            discovery.assert_not_called()


if __name__ == "__main__":
    unittest.main()
