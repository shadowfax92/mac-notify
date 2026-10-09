#ifndef MAC_NOTIFY_CLEAR_DARWIN_H
#define MAC_NOTIFY_CLEAR_DARWIN_H

enum { MNClearOK, MNClearPermissionDenied, MNClearFailed };

// Returned strings cross the C/Go boundary; the caller owns and frees them.
int mnClearNotifications(char **error);
char *mnTerminalApplication(void);

#endif
