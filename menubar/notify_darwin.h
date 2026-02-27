#ifndef NOTIFY_DARWIN_H
#define NOTIFY_DARWIN_H

void setupNotificationDelegate(void);
void requestNotificationAuth(void);
void sendDarwinNotification(const char *title, const char *body, const char *identifier);

#endif
