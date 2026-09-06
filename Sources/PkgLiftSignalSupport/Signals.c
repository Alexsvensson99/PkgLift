#include "PkgLiftSignalSupport.h"
#include <errno.h>
#include <signal.h>
#include <stdatomic.h>

// Signal delivery may occur on any Swift executor thread. Only lock-free atomic
// operations run in the handler: no Swift, allocation, locks, or filesystem I/O.
_Static_assert(ATOMIC_INT_LOCK_FREE == 2, "Signal capture requires lock-free int atomics");
static _Atomic int active = 0;
static _Atomic int received = 0;
static struct sigaction previous_int;
static struct sigaction previous_term;

static void record_signal(int number) {
    int expected = 0;
    atomic_compare_exchange_strong_explicit(
        &received, &expected, number, memory_order_relaxed, memory_order_relaxed);
}

int pkglift_signals_install(void) {
    int expected = 0;
    if (!atomic_compare_exchange_strong(&active, &expected, 1)) {
        return EBUSY;
    }
    atomic_store(&received, 0);
    struct sigaction action = {0};
    action.sa_handler = record_signal;
    action.sa_flags = SA_RESTART;
    sigemptyset(&action.sa_mask);
    sigaddset(&action.sa_mask, SIGINT);
    sigaddset(&action.sa_mask, SIGTERM);
    if (sigaction(SIGINT, &action, &previous_int) != 0) {
        int failure = errno;
        atomic_store(&active, 0);
        return failure;
    }
    if (sigaction(SIGTERM, &action, &previous_term) != 0) {
        int failure = errno;
        sigaction(SIGINT, &previous_int, 0);
        atomic_store(&active, 0);
        return failure;
    }
    return 0;
}

int pkglift_signals_received(void) {
    return atomic_load_explicit(&received, memory_order_relaxed);
}

int pkglift_signals_restore(void) {
    // Keep ownership on failure; never allow a second installation to save our
    // handler as the previous disposition.
    if (sigaction(SIGINT, &previous_int, 0) != 0) return errno;
    if (sigaction(SIGTERM, &previous_term, 0) != 0) return errno;
    atomic_store(&active, 0);
    return 0;
}
