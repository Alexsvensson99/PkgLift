#ifndef PKGLIFT_SIGNAL_SUPPORT_H
#define PKGLIFT_SIGNAL_SUPPORT_H

// One apply per executable process. Concurrent owners are refused with EBUSY;
// after any possible handler dispatch, finished ownership is never reused and a
// later installation is refused with EALREADY. Returns zero or an errno.
int pkglift_signals_install(void);
int pkglift_signals_received(void);
// Call only after migration has completed or its rollback attempt has finished.
// Restore both dispositions and atomically close the outcome. If succeeded is
// nonzero, return a recorded signal or let a delayed handler terminate with its
// conventional status. If zero, preserve the caller's existing failure instead.
int pkglift_signals_finish(int succeeded, int *received_signal);

#endif
