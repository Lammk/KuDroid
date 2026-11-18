// Guest signal handling: the guest's sigaction, translated rather than forwarded.

































#ifndef KUDROID_ABI_GUESTSIGNALS_H
#define KUDROID_ABI_GUESTSIGNALS_H

#include <cstdint>

namespace kudroid {

// `struct sigaction` as a 64-bit Android guest sees it.
//
// Copied field for field from bionic's __SIGACTION_BODY under `#if defined(__LP64__)`
// (libc/include/bits/signal_types.h). The layout follows from the declaration under
// LP64 rules, so it is right on any host with the same ABI — no offsets are hard-coded
// here beyond the static_asserts that pin them.
struct GuestSigaction {
    int32_t sa_flags;
    // The union bionic declares. Kept as a raw pointer because this side never calls
    // it directly: dispatch goes through guest_signal_dispatch, which builds the
    // arguments the guest expects.
    void* sa_handler_or_sigaction;
    // sigset_t on LP64 bionic is a bare unsigned long, and it is a Linux signal
    // bitmask: bit (n-1) is Linux signal n, not the host's n.
    uint64_t sa_mask;
    void (*sa_restorer)(void);
};

// The number of signals a Linux guest can name (bionic's NSIG is 65).
constexpr int kGuestNSIG = 65;

// Translate a signal number between the guest's Linux numbering and the host's.
// Returns 0 for a number with no counterpart, which callers must treat as EINVAL
// rather than passing on.
int guest_signal_to_host(int guest_signum);
int host_signal_to_guest(int host_signum);

// Translate guest signal-action structures and flags.






int guest_sigaction(int guest_signum, const GuestSigaction* act, GuestSigaction* oldact);

// Run the guest's handler for a signal that has just arrived on a host signal number.








bool guest_signal_dispatch(int host_signum, void* host_siginfo, void* host_ucontext);

// Whether the guest has a handler installed for a host signal number. Cheap; for a
// caller that wants to know before doing expensive work.
bool guest_signal_has_handler(int host_signum);

// True while some thread is inside a guest handler for an asynchronous signal.
// A managed runtime parks every thread in exactly such a handler to stop the world,
// and a parked thread keeps whatever lock it held. Code that runs meanwhile on the
// remaining threads (the collector itself) must not take diagnostic locks or touch
// stdio: it would wait on a lock whose owner only resumes after the collector is done.
// Lock-free; safe from any context.
bool guest_async_handler_active();

// The guest's sigaltstack. Separate from the host's because Linux's stack_t is
// {sp, flags, size} and Darwin's is {sp, size, flags} — read through the wrong one, a
// guest asking for a 64KB alternate stack passes ss_flags=65536, the host rejects it,
// and the guest carries on believing it has an alternate stack it does not have.
int guest_sigaltstack(const void* guest_ss, void* guest_oss);

// Translate guest signal delivery to host signal numbers.

















int guest_raise(int guest_signum);
int guest_kill(int pid, int guest_signum);
int guest_pthread_kill(unsigned long thread, int guest_signum);
int guest_tgkill(int tgid, int tid, int guest_signum);

// ── Blocking a signal ────────────────────────────────────────────────────────
//
// Two translations, not one. The signal numbers in the set, and `how` itself:
//
//     Linux : SIG_BLOCK=0  SIG_UNBLOCK=1  SIG_SETMASK=2
//     Darwin: SIG_BLOCK=1  SIG_UNBLOCK=2  SIG_SETMASK=3
//
// Forwarding `how` unchanged does not fail — it silently means something else. A guest
// blocking signals (Linux 0) passes 0, which is not any Darwin constant; a guest
// UNBLOCKING (Linux 1) passes 1, which Darwin reads as BLOCK. So a runtime that blocks
// its suspend signal around a critical section and unblocks it after ends up with the
// signal blocked permanently, and its GC hangs rather than crashing.
//
// `guest_set` and `guest_oldset` are Linux sigset_t: a bare 64-bit word where bit (n-1)
// is Linux signal n. Either may be null, as in the syscall.
int guest_sigprocmask(int guest_how, const uint64_t* guest_set, uint64_t* guest_oldset);

// sigsuspend and sigwait, for completeness: both take a Linux mask and both are
// reachable from a managed runtime's thread control.
int guest_sigsuspend(const uint64_t* guest_mask);
int guest_sigwait(const uint64_t* guest_set, int* guest_signum_out);

// The simple handler interface, which is still what a lot of guest code uses. Returns
// the previous handler, or SIG_ERR. Recorded through the same registry as sigaction so
// the two cannot disagree about what is installed.
void* guest_signal(int guest_signum, void* guest_handler);

// Test seam: drop every recorded guest handler. Not for use on a live guest.
void guest_signal_reset_for_test();

}  // namespace

#endif  // KUDROID_ABI_GUESTSIGNALS_H
