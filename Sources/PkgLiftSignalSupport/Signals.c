#include "PkgLiftSignalSupport.h"
#include <errno.h>
#include <signal.h>
#include <stdatomic.h>
#include <unistd.h>

// The executable runs one apply per process. Ownership is never reused after
// handlers may have been dispatched: an old handler has no generation token.
_Static_assert(ATOMIC_INT_LOCK_FREE == 2, "Signal capture requires lock-free int atomics");
static _Atomic int owner = 0; // 0 unused, 1 installed, 2 permanently closed
// 0 active, positive first signal, or one of the terminal states below.
static _Atomic int outcome = 0;
enum { completed = -1, failed = -2, late_exit_base = 128 };
static struct sigaction previous_int;
static struct sigaction previous_term;

static void record_signal(int number) {
    int expected = 0;
    if (atomic_compare_exchange_strong(&outcome, &expected, number)) return;

    // Atomically arbitrate with finish(), including a handler dispatched on
    // another thread but delayed before its first instruction. After successful
    // commit and disposition restoration, Swift cleanup is no longer needed.
    // Only lock-free atomics and async-signal-safe _exit run in this handler.
    if (expected == completed) {
        int terminal = -(late_exit_base + number);
        if (atomic_compare_exchange_strong(&outcome, &expected, terminal)) {
            expected = terminal;
        }
    }
    // All concurrent late handlers use the first terminal signal's exit status.
    if (expected <= -late_exit_base) _exit(-expected);
    // A recorded active signal is handled by Swift; a terminal failure retains
    // its original Swift/rollback/restoration error instead of being replaced.
}

int pkglift_signals_install(void) {
    int expected = 0;
    if (!atomic_compare_exchange_strong(&owner, &expected, 1)) {
        return expected == 1 ? EBUSY : EALREADY;
    }
    struct sigaction action = {0};
    action.sa_handler = record_signal;
    action.sa_flags = SA_RESTART;
    sigemptyset(&action.sa_mask);
    sigaddset(&action.sa_mask, SIGINT);
    sigaddset(&action.sa_mask, SIGTERM);
    if (sigaction(SIGINT, &action, &previous_int) != 0) {
        int failure = errno;
        atomic_store(&owner, 0); // No handler was installed.
        return failure;
    }
    if (sigaction(SIGTERM, &action, &previous_term) != 0) {
        int failure = errno;
        atomic_store(&outcome, failed);
        (void)sigaction(SIGINT, &previous_int, 0);
        atomic_store(&owner, 2);
        return failure;
    }
    return 0;
}

int pkglift_signals_received(void) {
    int value = atomic_load(&outcome);
    return value > 0 ? value : 0;
}

int pkglift_signals_finish(int succeeded, int *received_signal) {
    if (received_signal == 0) return EINVAL;
    *received_signal = 0;
    int expected_owner = 1;
    if (!atomic_compare_exchange_strong(&owner, &expected_owner, 2)) {
        return EALREADY;
    }
    if (!succeeded) atomic_store(&outcome, failed);

    // Attempt both restorations, retaining the first error. Failed restoration
    // must never arm handler-side successful-completion termination.
    int failure = 0;
    if (sigaction(SIGINT, &previous_int, 0) != 0) failure = errno;
    if (sigaction(SIGTERM, &previous_term, 0) != 0 && failure == 0) failure = errno;
    if (failure != 0) {
        atomic_store(&outcome, failed);
        return failure;
    }
    if (succeeded) {
        int expected = 0;
        if (!atomic_compare_exchange_strong(&outcome, &expected, completed)) {
            *received_signal = expected > 0 ? expected : 0;
        }
    }
    return 0;
}
