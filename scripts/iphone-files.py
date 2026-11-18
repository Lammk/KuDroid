#!/usr/bin/env python3
"""List an app's shared Documents folder over the native USB connection."""

import argparse
import asyncio
import sys

from pymobiledevice3.exceptions import PyMobileDevice3Exception
from pymobiledevice3.lockdown import create_using_usbmux
from pymobiledevice3.services.house_arrest import HouseArrestService
from pymobiledevice3.services.installation_proxy import InstallationProxyService


async def installed_bundle(lockdown, requested):
    async with InstallationProxyService(lockdown=lockdown) as service:
        exact = await service.get_apps(bundle_identifiers=[requested])
        if requested in exact:
            return requested
        apps = await service.get_apps(application_type="User")
    matches = [identifier for identifier in apps if identifier.endswith("." + requested)]
    if len(matches) != 1:
        raise RuntimeError(f"Could not uniquely resolve {requested}. Use -Action Apps and pass -BundleId explicitly.")
    return matches[0]


async def listing(args):
    lockdown = await create_using_usbmux(serial=args.udid)
    try:
        bundle = await installed_bundle(lockdown, args.bundle_id)
        if args.resolve_bundle_id:
            print(bundle)
            return
        async with await HouseArrestService.create(
            lockdown=lockdown, bundle_id=bundle, documents_only=not args.container
        ) as service:
            path = args.path if args.container else "/Documents/" + args.path.lstrip("/")
            for name in sorted(await service.listdir(path)):
                print(name)
    finally:
        await lockdown.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle-id", default="com.kudroid.shell")
    parser.add_argument("--path", default="/")
    parser.add_argument("--udid")
    parser.add_argument("--container", action="store_true")
    parser.add_argument("--resolve-bundle-id", action="store_true")
    parser.add_argument("--timeout", type=int, default=60)
    args = parser.parse_args()
    if args.timeout <= 0:
        parser.error("Timeout must be positive")
    asyncio.run(asyncio.wait_for(listing(args), args.timeout))


if __name__ == "__main__":
    try:
        main()
    except (PyMobileDevice3Exception, TimeoutError, OSError, RuntimeError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        print("Unlock and trust the phone. Use iphone.ps1 -Action Apps to find the installed bundle ID.", file=sys.stderr)
        sys.exit(1)
