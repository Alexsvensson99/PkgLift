#ifndef PKGLIFT_SIGNAL_SUPPORT_H
#define PKGLIFT_SIGNAL_SUPPORT_H

// Process-wide scope; concurrent owners are refused. Returns zero or an errno.
int pkglift_signals_install(void);
int pkglift_signals_received(void);
int pkglift_signals_restore(void);

#endif
