# KuDroid

For Windows build scripts, regression tests, xtool installation, and iPhone USB/file access, see [WINDOWS.md](WINDOWS.md).

> **KuDroid is not an emulator.**

### What is KuDroid?
KuDroid is an independent compatibility layer that runs Android apps on iOS.
It is not affiliated with, endorsed by, or certified by Google or Apple.
Android is a trademark of Google LLC.

The Android robot is reproduced or modified from work created and shared by Google
and used according to terms described in the Creative Commons 3.0 Attribution License.

The native core uses MIT; imported framework components retain their own licenses.
See [NOTICE](NOTICE) and [distribution requirements](docs/licensing.md).

---

### How it was made.
I vibecoded this. Please don't execute me

---

### Contributing & Pull Requests
- **Pull Requests**: I currently do not accept direct Pull Requests (PRs) to prevent breaking ongoing architectural changes and complex internal state. Sorry for any inconvenience caused!
- **Reporting Issues**: If you find bugs, crashes, or have feature suggestions, please **open an Issue** on GitHub. I will investigate and fix it directly.
- **Forks**: You are completely free to **fork** the repository and experiment with your own modifications!

---

### Key Technical Highlights
- **KuART (KuDroid Android Runtime)**: Standalone, lightweight DEX bytecode interpreter tailored for Apple Silicon (ARM64), reading directly from `.apk`.
- **Native Metal Graphics**: Bridges Android Surface / OpenGL ES 3.0 via ANGLE directly to Apple's CAMetalLayer for best rendering.
- **Low-Latency Audio**: Seamless translation from Android OpenSL ES / AAudio to iOS CoreAudio (AudioToolbox).
- **Bionic Translation Shim**: Re-links Android ELF shared libraries (`.so`) to Mach-O POSIX syscalls on Darwin.

---
### For iOS 26,27
- Attach universal.js in StikDebug to enable JIT
- Or use self pairing JIT

### App configuration
- First open offers an optional memory budget and asks whether to download and install the official microG APKs. Licenses and artifact details are in [third_party/microg](third_party/microg).
- Hold an app and choose **Configure** to set its memory percentage or turn microG off. New apps inherit the defaults in Settings; per-app choices survive updates.
- The memory slider covers 40–95%. Tap the percentage to type another value. Values outside 0–100 cannot be saved; 0% and 100% disable budgeting. Other values outside the slider range require confirmation.
- The budget reports a share of measured available memory to Android and sends low-memory callbacks. It is advisory: native allocations can exceed it, so it cannot guarantee prevention of an iOS memory kill.
- Reversed apps offer a saved memory budget on the JIT screen and use StikDebug or an external debugger. Already-enabled JIT launches directly.

microG packages are shared within the guest runtime. Signature spoofing is limited to installed shared packages that request it and provide signature metadata. Individual Android service APIs still require compatibility support.

---

### Credits & Acknowledgements
- **Special thanks to `sakayorii`** 

Note: JIT is needed,nothing will load without it
