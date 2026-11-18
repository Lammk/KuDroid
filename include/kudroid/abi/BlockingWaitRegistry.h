// Track blocking waits for thread diagnostics.




















#ifndef KUDROID_ABI_BLOCKINGWAITREGISTRY_H
#define KUDROID_ABI_BLOCKINGWAITREGISTRY_H

#include <cstdint>

namespace kudroid {

// Which primitive a thread is parked on. Named rather than a string so entering a
// wait cannot allocate or format.
enum class WaitKind : int {
    kNone = 0,
    kFutex,          // FUTEX_WAIT with no timeout — waits forever by construction
    kFutexTimed,     // FUTEX_WAIT with a timeout; reported only if it overruns badly
    kSemaphore,      // sem_wait
    kSemaphoreTimed, // sem_timedwait
    kMutex,          // pthread_mutex_lock
    kCondition,      // pthread_cond_wait (no timeout)
    kConditionTimed, // Track contended monitor acquisition.


    kJavaMonitor,
    // Track threads waiting on released monitors.
















    kJavaWait,
    kRwlockRead,     // pthread_rwlock_rdlock
    kRwlockWrite,    // pthread_rwlock_wrlock
    kOnce,           // pthread_once, waiting for another thread's initialiser
    kEpoll,          // epoll_wait with an indefinite timeout
    kLooperPoll,     // ALooper_pollAll/pollOnce (fd set + wake pipe)
    // pthread_join: waits for another thread to exit, and therefore inherits whatever
    // is blocking that thread. A join is the one wait whose report is only half the
    // story on its own — the other half is the target's own stalled line.
    kJoin,
    // Track static-initializer guard retry loops.





    kGuardSpin,
};

// Declare that this thread is entering a blocking wait.








void blocking_wait_begin(WaitKind kind, const void* object, const void* caller);

// Clear this thread's declaration. Safe to call when nothing was declared.
void blocking_wait_end();

// Note that a tracked wait is still going round its retry loop. Only meaningful for
// kGuardSpin, where there is no single blocking call to sit inside: the count is
// what distinguishes "briefly contended" from "spinning forever", and it appears in
// the stalled report.
void blocking_wait_note_iteration();

// Attach one number to this thread's current wait, reported as owner=N.
//
// For kGuardSpin it is the tid recorded in the guard word — the thread running the
// static initialiser. That is the mssing half of a stall report: knowing a thread is
// spinning on guard X is not actionable, but "spinning on X, owned by tid Y" pairs
// directly with Y's own stalled line and names the whole cycle.
void blocking_wait_note_owner(uint64_t owner);

// Record the requested wait duration.













void blocking_wait_note_budget(uint64_t budget_ms);

// The first return address that lies inside a guest module, or the immediate caller when none does.






const void* guest_return_address(int frames);

// RAII form. Prefer this: an early return out of a wait path that forgot to call
// blocking_wait_end would leave a phantom entry and produce a false report.
class BlockingWaitScope {
public:
    BlockingWaitScope(WaitKind kind, const void* object, const void* caller) {
        blocking_wait_begin(kind, object, caller);
    }
    ~BlockingWaitScope() { blocking_wait_end(); }
    BlockingWaitScope(const BlockingWaitScope&) = delete;
    BlockingWaitScope& operator=(const BlockingWaitScope&) = delete;
};

// Report every wait that has been outstanding longer than `threshold_ms`, once per
// wait. Called from the telemetry watchdog thread; returns how many it reported so
// the caller can tell "nothing is stuck" from "the scan did not run".
//
// A wait a thread PARKED ITSELF in with no deadline and no owner — kJavaWait, an
// unbounded Object.wait() — is not reported here. That is not a stall; it is a thread
// with nothing to do, and it is indistinguishable from one only by what it is waiting
// for. See blocking_wait_report_idle().
int blocking_wait_report_stalled(uint64_t threshold_ms);

// Report long-idle waits, at a lower severity and a much higher threshold.








int blocking_wait_report_idle(uint64_t threshold_ms);

// Number of waits currently outstanding. For tests, and for a summary line.
int blocking_wait_active_count();

// Test seam: drop all state. Not for use on a live guest.
void blocking_wait_reset_for_test();

}  // namespace

#endif  // KUDROID_ABI_BLOCKINGWAITREGISTRY_H
