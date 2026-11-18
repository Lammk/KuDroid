#pragma once

#include <cstddef>
#include <cstdint>

namespace kudroid {

void native_run_begin();
void native_phase(const char* phase);

// A native call can outlive every crash handler when the OS terminates the
// process. These hooks maintain a small, durable diagnostic record for that
// case. The implementation is intentionally independent of any guest app.
//
// Calls NEST: a native method re-enters Java, which calls another native method.
// Each of these pushes onto the calling thread's own stack, so the record of the
// outer call survives the inner one returning. Getting that wrong is not a cosmetic
// problem — see the comment on call_report_snapshot().
void native_call_enter(const char* class_name, const char* method,
                       const char* signature, int vm_lock_depth);
void native_call_stage(const char* stage);
void native_call_exit();

// Wait for active rendering calls before removing the GPU layer.

int native_frame_in_flight();

// Tell the watchdog a thread has taken a fatal signal.









void native_note_fatal_signal(int signal_number, unsigned long long thread_id);

// Track the shallow lifecycle portion of Java execution without logging every
// interpreter frame in a busy application.
bool java_call_should_trace(const char* method, size_t depth);
void java_call_enter(const char* class_name, const char* method,
                     const char* signature, size_t depth);
void java_call_exit();

// What the watchdog would report right now.













struct CallReport {
    bool native_active = false;
    unsigned long long native_call_id = 0;
    unsigned long long native_thread_id = 0;
    unsigned long long native_elapsed_ms = 0;
    int native_vm_lock_depth = 0;
    // How many native calls are in flight on the reported thread. 1 means the
    // reported call is the only one; more means it called back into Java.
    unsigned native_stack_depth = 0;
    char native_class[256] = {};
    char native_method[256] = {};
    char native_signature[512] = {};
    char native_stage[64] = {};
    // The deepest call on the same thread, when it is not the reported one. This is
    // where execution actually is; the reported call is where it went in.
    char native_inner_class[256] = {};
    char native_inner_method[256] = {};
    char native_inner_stage[64] = {};

    bool java_active = false;
    unsigned long long java_thread_id = 0;
    unsigned long long java_elapsed_ms = 0;
    size_t java_depth = 0;
    char java_class[256] = {};
    char java_method[256] = {};
    char java_signature[512] = {};
};

CallReport call_report_snapshot();

// Test seam: drop all call records. Not for use on a live guest.
void call_telemetry_reset_for_test();

}  // namespace
