// kudroid_bridge.cpp — core wiring only: boot markers, log-directory
// ownership and the log-clearing entry point. Everything else that used to
// live in this file is now in src/bridge/:
//
//   BridgeState      - directories, crash buffer, thread registry, log utils
//   BridgeShared     - cross-unit run/install/lifecycle state
//   CrashHandling    - signal handler, fault skip, JNI_OnLoad shield
//   ShellUI          - Metal layer, software canvas, haptics, keep-screen-on
//   GuestLibrary     - JVM self-test, guest dlopen/dlsym, run_apk
//   AppLifecycle     - install, JIT probe, orientation, soft input, stop
//   DiagnosticTests  - ELF/SO tests, app deletion, APK load, DEX translate
#include "kudroid/kudroid_bridge.h"
#include "bridge/BridgeState.h"
#include "bridge/BridgeShared.h"
#include "bridge/CrashHandling.h"
#include "kudroid/KuArtRuntime.h"
#include "kudroid/VFSPathRemapper.h"
#include "kudroid/PermissionManager.h"
#include "kudroid/Log.h"

#include <cstdio>
#include <cstring>
#include <mutex>
#include <chrono>
#include <filesystem>
#include <string>
#include <atomic>

#include <fcntl.h>
#include <pthread.h>
#include <unistd.h>

#if defined(__APPLE__)
#include <mach/mach.h>
#include <mach/task.h>
#else
#include <sys/syscall.h>
#endif

extern "C" int kudroid_android_log_message(int priority, const char* tag, const char* message);

// Boot-relative clock shared by the phase marks and by every trace line, so a
// VFS/audio line lands on the same timeline as the [KuDroidBoot] marks around it.
static std::atomic<long long> g_bootT0Ns{0};

static long long boot_now_ms(void) {
    const long long ns = std::chrono::duration_cast<std::chrono::nanoseconds>(
                             std::chrono::steady_clock::now().time_since_epoch())
                             .count();
    long long t0 = g_bootT0Ns.load(std::memory_order_relaxed);
    if (t0 == 0) {
        g_bootT0Ns.store(ns, std::memory_order_relaxed);
        t0 = ns;
    }
    return (ns - t0) / 1000000;
}

extern "C" void kudroid_boot_mark(const char* phase) {
    char line[192];
    std::snprintf(line, sizeof(line), "[KuDroidBoot] t=%lldms %s",
                  boot_now_ms(), phase ? phase : "?");
    std::fprintf(stderr, "%s\n", line);
    kudroid_android_log_message(4, "KuDroidBoot", line);
}

// Prefix for one diagnostic line: boot-relative time plus the guest thread name.





extern "C" const char* kudroid_trace_stamp(void) {
    static thread_local char buf[80];
    char name[64] = "?";
#if defined(__APPLE__)
    pthread_getname_np(pthread_self(), name, sizeof(name));
#else
    (void)pthread_getname_np(pthread_self(), name, sizeof(name));
#endif
    std::snprintf(buf, sizeof(buf), "[t=%lldms th=%s] ", boot_now_ms(), name);
    return buf;
}

extern "C" void kudroid_ios_diagnostic_phase(const char* phase) {
#if defined(__APPLE__)
    char line[512];
    snprintf(line, sizeof(line), "ios-phase=%s pid=%d", phase ? phase : "?", getpid());
    kudroid_persistent_breadcrumb(line);
#else
    (void)phase;
#endif
}

extern "C" void kudroid_ios_diagnostic_memory(const char* phase) {
#if defined(__APPLE__)
    task_vm_info_data_t info{};
    mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
    const kern_return_t kr = task_info(mach_task_self(), TASK_VM_INFO,
                                       reinterpret_cast<task_info_t>(&info), &count);
    if (kr == KERN_SUCCESS) {
        char line[768];
        snprintf(line, sizeof(line),
                 "ios-memory phase=%s pid=%d phys_footprint=%llu resident=%llu virtual=%llu",
                 phase ? phase : "?", getpid(),
                 static_cast<unsigned long long>(info.phys_footprint),
                 static_cast<unsigned long long>(info.resident_size),
                 static_cast<unsigned long long>(info.virtual_size));
        kudroid_persistent_breadcrumb(line);
    }
#else
    (void)phase;
#endif
}

extern "C" void kudroid_set_log_paths(const char* dir, const char* logDirectory) {
    if (!bridgeConfigureLogPaths(dir, logDirectory)) return;
    crashNoteMainThread();
    const char* currentDirectory = kudroid_current_log_dir();

    installCrashHandlers();
    // Answer the platform-register question once, before any guest code runs:
    // guest binaries reserve x18 for a live address, and the fix for that
    // depends on whether a delivery preserves it.
    kudroid_probe_platform_register();
    // Write the build stamp to its own file so the running version can be checked
    // without reading a log, which answers "is the iPhone still on the old build?".
    const char* stamp = kudroid_build_stamp();
    writeLogFile("kudroid_version.txt", std::string(stamp) + "\n");

    // Store missing-class diagnostics beside the other logs.
    std::string classesLogPath = (std::filesystem::path(currentDirectory) / "classes.log").string();
    kuart_set_missing_class_log_path(classesLogPath.c_str());

    // The breadcrumb journal is the only place silently-recovered faults
    // (fault-skipped, null-run, skip refused) and the watchdog's thread dumps
    // are recorded, so its absence is what makes an intermittent crash
    // uninvestigable after the fact. Prove it is writable now, while this is
    // ordinary code, rather than letting the fatal path discover it cannot
    // write -- the breadcrumb writer itself is called from the signal handler
    // and so cannot do this reporting itself.
    {
        const std::string probe = std::string(currentDirectory) + "/native_breadcrumbs.log";
        const int fd = ::open(probe.c_str(), O_WRONLY | O_CREAT | O_APPEND, 0644);
        if (fd < 0) {
            fprintf(stderr, "[kudroid_core] breadcrumb journal not writable: %s (%s)\n",
                    probe.c_str(), std::strerror(errno));
        } else {
            ::close(fd);
        }
    }
}

extern "C" void kudroid_set_log_dir(const char* dir) {
    if (!dir || !*dir) return;
    const std::string logs = std::string(dir) + "/logs";
    kudroid_set_log_paths(dir, logs.c_str());
}

// Debug-tab toggle for per-JNI-call tracing (replaces the TEMP-DEBUG hardcode
// and the Xcode-scheme env var, neither of which survives a real workflow).
extern "C" void kudroid_log_set_jni(int enabled) {
    kudroid::log::set_jni(enabled != 0);
}

extern "C" int kudroid_log_get_jni(void) {
    return kudroid::log::jni_enabled() ? 1 : 0;
}

extern "C" void kudroid_android_log_force_reopen(void);

extern "C" void kudroid_clear_all_logs(void) {
    const char* logDirectory = kudroid_current_log_dir();
    if (!*logDirectory) return;
    bridgeClearCurrentLogFiles();

    // 3. Clear in-memory crash log buffer
    {
        std::lock_guard<std::mutex> lock(g_crashBufMtx);
        g_crashLen = 0;
        g_abortMessage[0] = '\0';
    }

    // 4. Create fresh, clean kudroid_android_logs.txt (truncate/write)
    char aPath[1200];
    snprintf(aPath, sizeof(aPath), "%s/kudroid_android_logs.txt", logDirectory);
    FILE* afp = fopen(aPath, "w");
    if (afp) {
        fprintf(afp, "[kudroid_core] process-start Build: %s\n", kudroid_build_stamp());
        fclose(afp);
        ::chmod(aPath, 0644);
    }

    // The android-log sink caches its descriptor by directory name; the remove
    // + recreate above swapped the file's inode under it, so every later log
    // line kept appending to the unlinked old file. Force the reopen.
    kudroid_android_log_force_reopen();
#if defined(__APPLE__)
    // 5. Truncate/create fresh stderr.log
    char errPath[1200];
    snprintf(errPath, sizeof(errPath), "%s/stderr.log", logDirectory);
    int errFd = open(errPath, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (errFd >= 0) {
        dup2(errFd, STDERR_FILENO);
        setvbuf(stderr, nullptr, _IONBF, 0);
        close(errFd);
        ::chmod(errPath, 0644);
        fprintf(stderr, "[kudroid_core] process-start Build: %s\n", kudroid_build_stamp());
        fprintf(stderr, "[kudroid_core] log directory: %s\n", logDirectory);
        kudroid_boot_mark("start");
    }
#endif

    // 6. Write fresh version stamp
    const char* stamp = kudroid_build_stamp();
    writeLogFile("kudroid_version.txt", std::string(stamp) + "\n");

    // Reset the DEX runtime's missing classes log path.
    std::string classesLogPath = (std::filesystem::path(logDirectory) / "classes.log").string();
    kuart_set_missing_class_log_path(classesLogPath.c_str());
}

static void configure_documents_dir(const char* dir, bool flatRoot) {
    if (dir && dir[0] != '\0') {
        // Once per directory: the remapper's root is read by guest threads without a
        // lock, and re-applying it also resets the pseudo-files under it.
        static std::mutex s_documentsMutex;
        static std::string s_appliedDir;
        std::lock_guard<std::mutex> documentsLock(s_documentsMutex);
        const std::string key = std::string(dir) + (flatRoot ? ":flat" : ":android");
        if (s_appliedDir == key) return;
        s_appliedDir = key;
        kudroid::VFSPathRemapper::getInstance(false).setDocumentsDirectory(dir, flatRoot);
        kudroid::PermissionManager::getInstance().init(dir);

        bridgeRememberDocumentsDirectory(dir);
        const char* logDirectory = kudroid_current_log_dir();

        // classes.log is a diagnostic, so it follows the log directory rather than
        // Documents. This used to point it back at Documents and undo whatever
        // kudroid_set_log_dir had chosen — the two functions disagreed and the last
        // one called won.
        if (logDirectory[0] != '\0') {
            const std::string classesLogPath =
                (std::filesystem::path(logDirectory) / "classes.log").string();
            kuart_set_missing_class_log_path(classesLogPath.c_str());
        }
    }
}

extern "C" void kudroid_set_documents_dir(const char* dir) {
    configure_documents_dir(dir, false);
}

extern "C" void kudroid_set_standalone_root(const char* dir) {
    configure_documents_dir(dir, true);
}
