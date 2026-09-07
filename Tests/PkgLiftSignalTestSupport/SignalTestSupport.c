#include "PkgLiftSignalTestSupport.h"

#include <errno.h>
#include <signal.h>
#include <unistd.h>

static struct sigaction wrapped_action;
static int expected_signal = 0;
static int entered_pipe[2] = {-1, -1};
static int release_pipe[2] = {-1, -1};
static int completed_pipe[2] = {-1, -1};

static int transfer_byte(int descriptor, int should_write) {
    unsigned char byte = 1;
    ssize_t result;
    do {
        result = should_write
            ? write(descriptor, &byte, sizeof(byte))
            : read(descriptor, &byte, sizeof(byte));
    } while (result < 0 && errno == EINTR);
    return result == (ssize_t)sizeof(byte) ? 0 : EIO;
}

static void delayed_handler(int signal_number) {
    int saved_errno = errno;
    if (signal_number != expected_signal ||
        transfer_byte(entered_pipe[1], 1) != 0 ||
        transfer_byte(release_pipe[0], 0) != 0) {
        _exit(201);
    }

    wrapped_action.sa_handler(signal_number);

    if (transfer_byte(completed_pipe[1], 1) != 0) {
        _exit(202);
    }
    errno = saved_errno;
}

static void close_pipe(int descriptors[2]) {
    if (descriptors[0] >= 0) close(descriptors[0]);
    if (descriptors[1] >= 0) close(descriptors[1]);
    descriptors[0] = -1;
    descriptors[1] = -1;
}

static void close_all_pipes(void) {
    close_pipe(entered_pipe);
    close_pipe(release_pipe);
    close_pipe(completed_pipe);
}

int pkglift_test_delayed_signal_install(int signal_number) {
    if (signal_number != SIGINT && signal_number != SIGTERM) return EINVAL;
    if (expected_signal != 0) return EBUSY;

    if (pipe(entered_pipe) != 0 || pipe(release_pipe) != 0 || pipe(completed_pipe) != 0) {
        int failure = errno;
        close_all_pipes();
        return failure;
    }

    if (sigaction(signal_number, 0, &wrapped_action) != 0) {
        int failure = errno;
        close_all_pipes();
        return failure;
    }
    if ((wrapped_action.sa_flags & SA_SIGINFO) != 0 ||
        wrapped_action.sa_handler == SIG_DFL ||
        wrapped_action.sa_handler == SIG_IGN) {
        close_all_pipes();
        return ENOTSUP;
    }

    expected_signal = signal_number;
    struct sigaction wrapper = wrapped_action;
    wrapper.sa_handler = delayed_handler;
    wrapper.sa_flags &= ~SA_SIGINFO;
    if (sigaction(signal_number, &wrapper, 0) != 0) {
        int failure = errno;
        expected_signal = 0;
        close_all_pipes();
        return failure;
    }
    return 0;
}

int pkglift_test_delayed_signal_wait_until_entered(void) {
    if (expected_signal == 0) return EINVAL;
    return transfer_byte(entered_pipe[0], 0);
}

int pkglift_test_delayed_signal_release_and_wait(void) {
    if (expected_signal == 0) return EINVAL;
    int result = transfer_byte(release_pipe[1], 1);
    if (result != 0) return result;
    return transfer_byte(completed_pipe[0], 0);
}
