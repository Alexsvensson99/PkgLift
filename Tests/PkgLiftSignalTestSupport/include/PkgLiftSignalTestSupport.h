#ifndef PKGLIFT_SIGNAL_TEST_SUPPORT_H
#define PKGLIFT_SIGNAL_TEST_SUPPORT_H

// Wraps the currently installed handler for one signal and pauses before
// forwarding to it. These functions are linked only into PkgLiftCLITests.
int pkglift_test_delayed_signal_install(int signal_number);
int pkglift_test_delayed_signal_wait_until_entered(void);
int pkglift_test_delayed_signal_release_and_wait(void);

#endif
