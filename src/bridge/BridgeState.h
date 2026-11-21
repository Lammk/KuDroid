// BridgeState.h — shared state for the kudroid_bridge unit family.
//
// The original kudroid_bridge.cpp grew past five thousand lines, so it was
// split along its natural seams (crash handling, shell UI, guest library
// loading, app lifecycle, diagnostics). Everything several of those units
// share lives here: the Documents/logs directories, the crash buffer, the
// gentle-crash flags, and the thread-registry bookkeeping the sampler and the
// crash handler exchange.

#pragma once

#include <atomic>
#include <csignal>
#include <cstdint>
#include <mutex>
#include <string>
#include "LogPaths.h"


// Persist crash breadcrumbs before process termination.





extern char g_crashBuf[262144];
extern volatile sig_atomic_t g_crashLen;
extern std::mutex g_crashBufMtx;
extern char g_abortMessage[1024];
// si_code of the signal being reported, stored by the handler for tests and
// for readers that want signalled-vs-faulted without parsing the whole line.
extern volatile int g_crash_signal_si_code;

// Async-signal-safe thread id (gettid on Linux, pthread_threadid_np on Apple).
unsigned long long currentThreadIdForCrash(void);

// ── Persistent breadcrumb journal ────────────────────────────────────────────
//
// Append-only write(2) journal for diagnostics that must survive SIGKILL —
// see BridgeState.cpp for why fsync is deliberately NOT used here.
extern "C" void kudroid_persistent_breadcrumb(const char* line);

// ── Thread registry ──────────────────────────────────────────────────────────
//
// Numeric tids, plain atomic loads in the signal handler, stores only from
// normal context. Writers: thread sampler (names), GraphicsShim (render
// threads, frame presented), the guest UI dispatch. Readers: crash handler,
// watchdog, stall reports.
extern "C" {
void kudroid_note_thread_name(const char* name);
void kudroid_note_guest_ui_thread(void);
unsigned long long kudroid_guest_ui_thread_id(void);
void kudroid_fault_state_reset_for_app(void);
void kudroid_note_render_thread(void);
void kudroid_note_frame_presented(void);
uint64_t kudroid_last_frame_presented_ns(void);
uint64_t kudroid_run_started_ns(void);
void kudroid_frame_presented_reset(void);
}

// ── Gentle crash API ─────────────────────────────────────────────────────────
//
// Append to the in-memory crash buffer (single-line, ring-compacted).
// android_set_abort_message shim: capture guest abort message for crash
// reporting. Snapshot of the crash buffer, malloc'd; caller frees. For tests.
extern "C" {
void kudroid_append_crash_log(const char* text, size_t len);
void kudroid_store_abort_message(const char* msg);
const char* kudroid_crash_log_snapshot(void);
}

// ── Shared log-file utilities (defined in BridgeState.cpp) ───────────────────
//
// Every bridge unit writes its diagnostic files through these so the "where do
// logs go" answer stays in one place.

// Write a named file in the selected diagnostic directory.
// These were internal to the old monolith; now shared across the bridge units.
void writeLogFile(const char* name, const std::string& content);

// Append to kudroid_crash.log in the selected directory.
void appendCrashLogFile(const std::string& content);

// Mirror a rendered crash report into the in-memory crash buffer.
void mirrorCrash(const std::string& log);

// Log through the android sink, stripping the "[kudroid_core] " prefix the
// sink's tag already carries (see BridgeState.cpp for the duplicate-tag story).
void logCoreLine(int priority, const std::string& line);

// Standard header for test logs: build stamp + test name + timestamp.
void appendTestHeader(std::string& log, const char* test, const char* path);

// Append the crash-buffer snapshot to `log` under a section header. No-op when
// the buffer is empty.
void appendCrashSnapshot(std::string& log, const char* sectionName);

// Copy the last maxLines lines of src into dst. Shared by the crash handler
// ("log up to crash" modal tail) and tests.
void extractLastLines(const char* src, size_t srcLen, char* dst, size_t dstCap,
                      int maxLines = 30);

// "build <version> (<git-hash>)" from the KUDROID_GIT_HASH compile definition.
extern "C" const char* kudroid_build_stamp(void);

// One-shot probe of executable-memory capability; defined in AppLifecycle.cpp.
// Used by appendTestHeader to stamp test logs with the JIT verdict.
int kudroid_jit_available(void);

// Library residency: guest .so mappings live for the process lifetime
// (unmapping under a detached thread aborts), so a run started after an
// install would reuse stale code. The run entry marks residency and refuses a
// tainted run; installs bump the generation (AppLifecycle).
void bridgeMarkLibsResident(uint64_t generation);
bool bridgeLibsResident(uint64_t* generationOut);
