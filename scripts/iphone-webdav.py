#!/usr/bin/env python3
"""Expose an application's shared Documents folder to Windows Explorer."""

import argparse
import asyncio
from functools import cached_property
import logging

import uvicorn
from asgi_webdav.config import generate_config_from_dict, reinit_global_config
from asgi_webdav.constants import DAVPath, DAVTime
from asgi_webdav.server import DAVApp
from asgi_webdav.web_dav import PrefixProviderInfo
from pymobiledevice3.exceptions import PyMobileDevice3Exception
from pymobiledevice3.lockdown import create_using_usbmux
from pymobiledevice3.services.house_arrest import HouseArrestService
from pymobiledevice3.services.webdav import AfcDavProvider


class ExplorerTime(DAVTime):
    @cached_property
    def iso_8601(self):
        # The redirector requires UTC dates without fractional seconds.
        return self.data.strftime("%Y-%m-%dT%H:%M:%SZ")


class ExplorerProvider(AfcDavProvider):
    async def _create_dav_property_obj(self, href_path, stat_result):
        result = await super()._create_dav_property_obj(href_path, stat_result)
        result.basic_data.creation_date = ExplorerTime(result.basic_data.creation_date.timestamp)
        return result


async def serve(args):
    lockdown = await asyncio.wait_for(create_using_usbmux(serial=args.udid), 20)
    try:
        service = await asyncio.wait_for(HouseArrestService.create(
            lockdown=lockdown, bundle_id=args.bundle_id, documents_only=True,
        ), 20)
        async with service:
            config = generate_config_from_dict({
                "account_mapping": [{"username": "anonymous", "password": "", "permissions": ["+"]}],
                "anonymous": {
                    "enable": True,
                    "user": {"username": "anonymous", "password": "", "permissions": ["+"]},
                    "allow_missing_auth_header": True,
                },
                "provider_mapping": [],
                "logging": {"enable": False},
            })
            reinit_global_config(config)
            app = DAVApp(config)
            provider = ExplorerProvider(
                afc=service, root="/Documents", config=config,
                prefix=DAVPath("/"), read_only=args.readonly,
            )
            app.web_dav.prefix_provider_mapping = [PrefixProviderInfo(
                prefix=DAVPath("/"), prefix_weight=1, provider=provider,
                home_dir=False, read_only=args.readonly, ignore_property_extra=True,
            )]
            server = uvicorn.Server(uvicorn.Config(
                app, host="127.0.0.1", port=args.port, log_level="warning",
                lifespan="off", timeout_graceful_shutdown=5,
            ))
            server_task = asyncio.create_task(server.serve())
            disconnect_task = asyncio.create_task(service.wait_terminated())
            try:
                done, _ = await asyncio.wait(
                    [server_task, disconnect_task], return_when=asyncio.FIRST_COMPLETED,
                )
                for task in done:
                    await task
            finally:
                server.should_exit = True
                await server_task
                disconnect_task.cancel()
                await asyncio.gather(disconnect_task, return_exceptions=True)
    finally:
        await lockdown.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle-id", required=True)
    parser.add_argument("--udid")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--readonly", action="store_true")
    args = parser.parse_args()
    if not 1024 <= args.port <= 65535:
        parser.error("Port must be between 1024 and 65535")
    logging.getLogger("asgi_webdav").setLevel(logging.WARNING)
    asyncio.run(serve(args))


if __name__ == "__main__":
    try:
        main()
    except (PyMobileDevice3Exception, OSError, TimeoutError) as error:
        raise SystemExit(f"ERROR: {error}") from error
