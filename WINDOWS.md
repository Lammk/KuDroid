# Windows development

xtool supports Windows through WSL, as described in its [installation guide](https://xtool.sh/documentation/xtooldocs/installation-linux).
The runtime and host regressions use POSIX APIs, so the iOS C++ build and native regression binaries run inside Ubuntu 26.04 LTS.
Python 3.9 or newer is required on Windows; the scripts use the `python` command.
Run repository commands from the root of your checkout. Choose your own checkout and download locations.

## Install the tools

Install or update WSL, then install Ubuntu 26.04 from an Administrator PowerShell:

```powershell
winget install --id Microsoft.WSL --exact --source winget
wsl --install -d Ubuntu-26.04
```

Restart Windows if the installer requests it. Open Ubuntu once and finish creating your Linux user.
On an older Windows 10 installation where packaged WSL reports `WSL_E_OS_NOT_SUPPORTED`,
the built-in WSL 2 engine can import Ubuntu's official image directly:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\install-ubuntu.ps1
```

This verifies the image checksum against Microsoft's WSL manifest, installs `Ubuntu-26.04`,
and creates `kudroid` as its normal default user. It does not replace existing distributions.
Set that user's password with `wsl -d Ubuntu-26.04 -u root -- passwd kudroid` when you want interactive `sudo` access.

From the repository in a normal PowerShell, install the build dependencies, Swift 6.4, and xtool:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\setup-windows.ps1
```

The Swift toolchain installation has a bounded 3600-second deadline. Increase `-ToolchainTimeoutSeconds` for a slower connection.

Download the required **Xcode .xip archive** (Recommended Xcode 27.1) from [Apple Developer Downloads](https://developer.apple.com/download/all/?q=Xcode).
Sign in to Apple and accept the license in your browser. After the download finishes:

```powershell
$xcodeArchive = Read-Host 'Full path to the downloaded Xcode .xip archive'
powershell -ExecutionPolicy Bypass -File scripts\setup-windows.ps1 -XcodePath $xcodeArchive -Configure
```

Enter the path to your downloaded archive. `-XcodePath` installs the Apple SDK; `-Configure` runs interactive Apple authentication.
Enter credentials directly into xtool's prompt. You can also run `xtool setup` in Ubuntu.
In a fresh Ubuntu shell, load `~/.local/share/swiftly/env.sh` to put Swift on PATH and set `APPIMAGE_EXTRACT_AND_RUN=1` if AppImage cannot access FUSE.
Confirm installation with `swift --version`, `swift sdk list`, and `xtool --help`.

## Build

```powershell
powershell -ExecutionPolicy Bypass -File scripts\build-local-ios.ps1
powershell -ExecutionPolicy Bypass -File scripts\build-local-ios.ps1 -Configuration Release
powershell -ExecutionPolicy Bypass -File scripts\build-local-ios.ps1 -Clean -GlesBackend vulkan
powershell -ExecutionPolicy Bypass -File scripts\build-local-ios.ps1 -Run
```

The default matches the Linux script: Release C++ with Debug Swift. Explicit `-Configuration Debug` or `-Configuration Release` sets both to that configuration.
`-Run` builds and installs through xtool after a USB connection or the Windows USB service relay is configured.
The IPA build includes the existing launcher, runtime, and system-font verification steps.
The resulting IPA is copied to `ios-app\KuDroidShell\xtool\KuDroidShell.ipa` in your Windows checkout.

Builds synchronize the current checkout, including local source changes, into a dedicated WSL copy under `~/.cache/kudroid-windows/`.
Synchronization compares file checksums and verifies the copied contents before building.
This avoids spaces in toolchain paths, copied Linux build caches, and CRLF shell scripts. Shell normalization affects only that copy.
Upstream AOSP/ART audit trees and unused graphics build tools are excluded; compiled sources, framework inputs, and packaged assets are retained.
Build directories are `build-ios-windows` and `build-host-windows` inside the copy; `-Clean` removes only its iOS build caches.
Do not edit the WSL source copy: each invocation synchronizes it from Windows.
Each build step defaults to a 600-second timeout; increase `-TimeoutSeconds` for a slow initial build.
All wrappers accept `-Distribution` if you use a different distribution name.

## Framework and regressions

The Java framework can also build directly on Windows with JDK 17 and the pinned `third_party\d8\d8.jar` or `r8.jar`:

```powershell
powershell -ExecutionPolicy Bypass -File framework\build.ps1 -RequireD8
```

This uses an empty boot classpath, Java 8 bytecode, D8 API 29, and the existing pinned Kotlin libraries.
Compilation uses an argument file and a class JAR to handle spaces and Windows command-length limits.
`-NoEmbed` builds only the DEX. Compilation steps default to a 240-second timeout.

```powershell
powershell -ExecutionPolicy Bypass -File scripts\test-windows.ps1
powershell -ExecutionPolicy Bypass -File scripts\test-windows.ps1 -Suite framework
powershell -ExecutionPolicy Bypass -File scripts\test-windows.ps1 -Suite posix
powershell -ExecutionPolicy Bypass -File scripts\test-windows.ps1 -Suite arm64
powershell -ExecutionPolicy Bypass -File scripts\test-windows.ps1 -Suite probes
```

| Suite | Coverage |
| --- | --- |
| `all` | All four regression suites below |
| `core` | The selected host binaries enabled with `KUDROID_BUILD_HOST_TESTS=OFF` |
| `framework` | Framework startup, modules, services, surface lifecycle, and Android TLS |
| `posix` | Native looper, guest alternate signal stack, and GCD timer deadlines |
| `arm64` | JNI trampoline, guest varargs, and generated JIT execution under QEMU |
| `probes` | Build freestanding ARM64 guest `.so` probes and copy them to `build\test-so` |

`-SkipBuild` reuses the WSL host binaries for core/framework/ARM64 checks; the TLS harness still performs its own incremental build.
Use `-BuildTimeoutSeconds` and `-TestTimeoutSeconds` to change deadlines. Missing ARM64 tools fail explicitly instead of reporting a successful skip.
The `probes` suite requires the guest C sources under `tests/so`; it fails explicitly if those inputs are absent.
The existing Linux scripts remain available.

## iPhone USB and app folders

Windows Explorer exposes the phone's media interface, not all iOS app sandboxes.
Install Apple's **Apple Devices** app or iTunes for the Apple Mobile Device USB driver, unlock the phone, and accept **Trust This Computer**.
An app with `UIFileSharingEnabled` appears under **Files** in Apple Devices or **File Sharing** in iTunes.
The shell already enables this setting. Its Documents folder should be available there.
iOS restricts full container access; a folder browser cannot grant access that the installed app does not permit.

For direct access through Apple's Windows USB service, install the device tools once:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\iphone.ps1 -Action InstallTools
powershell -ExecutionPolicy Bypass -File scripts\iphone.ps1 -Action Devices
powershell -ExecutionPolicy Bypass -File scripts\iphone.ps1 -Action List
powershell -ExecutionPolicy Bypass -File scripts\iphone.ps1 -Action Browse -TimeoutSeconds 3600
powershell -ExecutionPolicy Bypass -File scripts\iphone.ps1 -Action Pull -RemotePath /logs -LocalPath .\logs
powershell -ExecutionPolicy Bypass -File scripts\iphone.ps1 -Action Push -LocalPath .\example.apk -RemotePath /example.apk
```

These default to the shared Documents folder of `com.kudroid.shell`.
The helper resolves a unique signing prefix automatically. Use `-Action Apps` and pass `-BundleId` explicitly if more than one installed app matches.
Pass `-Udid` when multiple phones are connected. `-Container` requests the full app container only where iOS permits it.
Tools are installed in `%USERPROFILE%\.kudroid\device-tools`, separate from your system Python.

### Open Documents as an Explorer drive

With the phone connected and trusted, map the shared Documents folder directly to `K:`:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\iphone-explorer.ps1 -Open
powershell -ExecutionPolicy Bypass -File scripts\iphone-explorer.ps1 -Action Status
powershell -ExecutionPolicy Bypass -File scripts\iphone-explorer.ps1 -Action Unmount
```

The folder appears as **Kudroid Documents** under **This PC**. Explorer reads and writes
the real files on the phone; it does not synchronize a local copy. Use `-Drive L` if `K:`
is occupied, `-Port` if TCP 8765 is occupied, `-BundleId` for another shared app, or
`-ReadOnly` to prevent writes. The connection uses the existing device-tools environment
and Windows WebClient service, without another filesystem driver or Administrator access.

The hidden bridge listens only on `127.0.0.1` and exits when the phone disconnects.
Run the mount command again after reconnecting or restarting Windows. A desktop shortcut
to that command can reconnect and open the folder in one click. Logs and connection state
are under `%USERPROFILE%\.kudroid\iphone-explorer*`.

To mount automatically when the phone connects and start the watcher at Windows sign-in:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\iphone-explorer.ps1 -Action EnableAutoMount
powershell -ExecutionPolicy Bypass -File scripts\iphone-explorer.ps1 -Action AutoMountStatus
powershell -ExecutionPolicy Bypass -File scripts\iphone-explorer.ps1 -Action DisableAutoMount
```

Enabling with one connected USB phone remembers its UDID; pass `-Udid` to select one
explicitly. The hidden watcher checks Apple's USB service every three seconds, mounts
when the selected phone is available, and unmounts when it disconnects. Locked or untrusted
phones are retried every 30 seconds. USB-service errors preserve the current mapping.
The watcher also verifies that the Documents collection can be read through WebDAV.
If reinstalling the shell invalidates an existing AFC session, it reconnects the drive
even when the Python bridge process and Windows mapping are still present.
Drive operations are serialized so a desktop shortcut and the watcher can run together.
The watcher does not open Explorer windows automatically.

Autostart uses the current user's Windows Run registry entry, so Administrator access is
unnecessary. Configuration, watcher status, and logs are under `%USERPROFILE%\.kudroid\iphone-automount*`.
Disabling removes the startup entry and stops the watcher; the current drive remains available
until it is unmounted manually. Test connection transitions with the device-tools Python:
`python scripts\run-command.py --timeout 120 "$env:USERPROFILE\.kudroid\device-tools\Scripts\python.exe" scripts\test-iphone-automount.py`.

Windows WebClient defaults to a **50,000,000-byte file-transfer limit**. Larger files can
use the existing `iphone.ps1 -Action Pull` / `-Action Push` commands. Changing WebClient's
machine-wide `FileSizeLimitInBytes` setting requires Administrator access.

`iphone-webdav.py` uses the installed AFC WebDAV provider and formats creation dates as
UTC without fractional seconds, as required by the Windows WebDAV redirector.

xtool inside WSL also needs a USB connection. Microsoft's [USB passthrough guide](https://learn.microsoft.com/windows/wsl/connect-usb) uses usbipd:

```powershell
winget install --id dorssel.usbipd-win --exact --source winget
usbipd list
# Administrator PowerShell, once for the selected USB device:
usbipd bind --busid <BUSID>
# Normal PowerShell, while Ubuntu is running:
usbipd attach --wsl --busid <BUSID>
```

Confirm `idevice_id -l` and `xtool devices` in Ubuntu. Detach with `usbipd detach --busid <BUSID>` to return USB control to Windows.
While attached to WSL, Apple's Windows tools may lose access to the device.
If USB passthrough encounters an AFC mux error, xtool documents an [alternative using Apple's Windows USB service](https://github.com/xtool-org/xtool/issues/19#issuecomment-2898986718).
The repository includes that relay setup for systems using Apple's Windows USB service:

```powershell
# Administrator PowerShell:
powershell -ExecutionPolicy Bypass -File scripts\connect-iphone.ps1
```

The relay binds only the WSL gateway and permits only the current WSL guest address through the firewall.
Windows build wrappers read its saved address automatically, including `build-local-ios.ps1 -Run`.
`-Run` checks the saved gateway and guest address and verifies USB device discovery before synchronizing or building.
If the relay is stale or USB discovery fails, `-Run` automatically calls `connect-iphone.ps1` with administrator
elevation and retries once. Accept the Windows UAC prompt if shown. The retry reuses build caches, including
after `-Clean`; build and signing errors with a working USB connection retain their original exit status.
Relay repair has a 120-second deadline. Cancelling UAC or a failed repair stops the workflow.
For commands typed directly in Ubuntu, set `USBMUXD_SOCKET_ADDRESS` to the address printed by the script.
Run the relay script again if WSL's network addresses change.
