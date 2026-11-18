#pragma once

// Write diagnostics to the standard output, log file, and crash buffer.






namespace kudroid {
namespace log {

enum Level {
    kDebug = 2,  // verbose per-call (dlsym, egl forward, ...)
    kInfo  = 4,
    kWarn  = 5,
    kError = 6,
};

// Gate verbose: default ON (debugging real machine). Turn off using env
// KUDROID_LOG_VERBOSE=0 or kudroid_log_set_verbose(false).
void set_verbose(bool enabled);
bool verbose_enabled();

// Control per-call JNI tracing.



void set_jni(bool enabled);
bool jni_enabled();

// Gate the redundant per-call stage labels around the native trampoline
// (before-vm-release / before-trampoline / after-trampoline /
// before-result-decode). The native-enter and native-exit breadcrumbs are
// always written -- they are the record a crash investigation needs, and
// losing them is how an intermittent fault becomes uninvestigable. The four
// stage labels in between are the redundant middle of that pair, and they cost
// one synchronous unbuffered write() each into a process-wide O_APPEND file
// (native_breadcrumbs.log), so they are off by default and on under
// KUDROID_TRACE_HOT=1. RAM-only depth accounting
// (native_call_enter/exit, which the watchdog reads) is always on.
bool trace_hot();

// Write via standard pipeline (stdout + file + crash buffer).
void write(Level level, const char* tag, const char* fmt, ...)
    __attribute__((format(printf, 3, 4)));

} // namespace log

// Expose the logging macro.

using log::kDebug;
using log::kInfo;
using log::kWarn;
using log::kError;

} // namespace

// Always write by level (regardless of verbose).
#define KLOG(level, tag, ...) \
    ::kudroid::log::write((level), (tag), __VA_ARGS__)

// Only log when verbose is on — used for per-call logging that easily swallows the log file
// (dlsym resolution, egl forward each function...).
#define KLOGV(tag, ...)                                                     \
    do {                                                                    \
        if (::kudroid::log::verbose_enabled()) {                            \
            ::kudroid::log::write(::kudroid::log::kDebug, (tag), __VA_ARGS__); \
        }                                                                   \
    } while (0)

// Per-JNI-call lines: verbose-gated AND jni-gated. The second gate exists so
// verbose per-call logs elsewhere (dlsym, EGL) survive without the multi-kHz
// enter/exit stream from the JNI boundary.
#define KLOGJNI(tag, ...)                                                   \
    do {                                                                    \
        if (::kudroid::log::verbose_enabled() &&                            \
            ::kudroid::log::jni_enabled()) {                                \
            ::kudroid::log::write(::kudroid::log::kDebug, (tag), __VA_ARGS__); \
        }                                                                   \
    } while (0)
