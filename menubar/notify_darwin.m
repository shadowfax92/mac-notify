#import <UserNotifications/UserNotifications.h>
#import <Foundation/Foundation.h>

@interface NotifyDelegate : NSObject <UNUserNotificationCenterDelegate>
@end

@implementation NotifyDelegate
- (void)userNotificationCenter:(UNUserNotificationCenter *)center
       willPresentNotification:(UNNotification *)notification
         withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completionHandler {
    completionHandler(UNNotificationPresentationOptionBanner | UNNotificationPresentationOptionSound);
}
@end

static NotifyDelegate *_delegate = nil;

void setupNotificationDelegate(void) {
    _delegate = [[NotifyDelegate alloc] init];
    [[UNUserNotificationCenter currentNotificationCenter] setDelegate:_delegate];
}

void requestNotificationAuth(void) {
    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
    [center requestAuthorizationWithOptions:(UNAuthorizationOptionAlert | UNAuthorizationOptionSound | UNAuthorizationOptionBadge)
                         completionHandler:^(BOOL granted, NSError *error) {
        if (error) {
            NSLog(@"mac-notify: auth error: %@", error);
        }
    }];
}

void sendDarwinNotification(const char *title, const char *body, const char *identifier) {
    UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
    content.title = [NSString stringWithUTF8String:title];
    content.body = [NSString stringWithUTF8String:body];
    content.sound = [UNNotificationSound defaultSound];

    NSString *ident = [NSString stringWithUTF8String:identifier];
    UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:ident
                                                                          content:content
                                                                          trigger:nil];
    [[UNUserNotificationCenter currentNotificationCenter]
        addNotificationRequest:request
         withCompletionHandler:^(NSError *error) {
            if (error) {
                NSLog(@"mac-notify: notification error: %@", error);
            }
        }];
}
