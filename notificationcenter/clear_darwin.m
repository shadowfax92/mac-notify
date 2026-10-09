#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#include <unistd.h>
#include "clear_darwin.h"

static AXUIElementRef ax(id element) { return (__bridge AXUIElementRef)element; }
static NSTimeInterval now(void) { return NSProcessInfo.processInfo.systemUptime; }

// One CLI invocation owns the AX traversal and deadline. Notification Center
// updates its tree asynchronously: an accepted action is not proof of removal.
// Only settled empty snapshots count as success, and panel restoration gets its
// own deadline so failures during clearing cannot skip cleanup.
@interface MNClearSession : NSObject
@property NSTimeInterval deadline;
@property(copy) NSString *error;
@property NSUInteger visited;
- (id)attribute:(CFStringRef)name of:(id)element;
- (id)find:(NSString *)identifier in:(id)element depth:(NSUInteger)depth;
- (id)panel:(id)center;
- (BOOL)perform:(NSString *)action on:(id)element;
- (void)dismissals:(id)element into:(NSMutableArray *)result depth:(NSUInteger)depth;
@end

@implementation MNClearSession
- (id)attribute:(CFStringRef)name of:(id)element {
    if (self.error) return nil;
    if (now() >= self.deadline) {
        self.error = @"timed out clearing Notification Center; some notifications may remain";
        return nil;
    }
    CFTypeRef value = NULL;
    AXError status = AXUIElementCopyAttributeValue(ax(element), name, &value);
    if (status == kAXErrorSuccess) return CFBridgingRelease(value);
    // Missing optional attributes and vanished items are normal during dismissals.
    if (status != kAXErrorNoValue && status != kAXErrorAttributeUnsupported &&
        status != kAXErrorInvalidUIElement) {
        self.error = [NSString stringWithFormat:@"Accessibility could not read Notification Center (error %d)", status];
    }
    return nil;
}

- (id)find:(NSString *)identifier in:(id)element depth:(NSUInteger)depth {
    if (self.error) return nil;
    if (depth > 16 || ++self.visited > 1500) {
        self.error = @"Notification Center has an unsupported Accessibility layout";
        return nil;
    }
    if ([[self attribute:kAXIdentifierAttribute of:element] isEqual:identifier]) return element;
    NSString *role = [self attribute:kAXRoleAttribute of:element];
    if ([role isEqual:@"AXMenu"] || [role isEqual:@"AXOpaqueProviderGroup"]) return nil;
    for (id child in [self attribute:kAXChildrenAttribute of:element]) {
        id found = [self find:identifier in:child depth:depth + 1];
        if (found) return found;
    }
    return nil;
}

- (id)panel:(id)center {
    // Desktop widgets and on-screen banners also belong to NotificationCenter.
    // Banners even have the same AXSystemDialog subrole and window title as the
    // sliding panel. Only the panel exposes the widget editor, including when
    // history is empty; mistaking a banner for it skips opening the real history.
    for (id window in [self attribute:kAXWindowsAttribute of:center]) {
        if ([[self attribute:kAXSubroleAttribute of:window] isEqual:(__bridge NSString *)kAXSystemDialogSubrole]) {
            self.visited = 0;
            if ([self find:@"widget-editor-button" in:window depth:0]) return window;
        }
    }
    return nil;
}

- (BOOL)perform:(NSString *)action on:(id)element {
    AXError status = AXUIElementPerformAction(ax(element), (__bridge CFStringRef)action);
    if (status == kAXErrorSuccess || status == kAXErrorInvalidUIElement) return YES;
    self.error = [NSString stringWithFormat:@"Accessibility could not dismiss notifications (error %d)", status];
    return NO;
}

- (void)dismissals:(id)element into:(NSMutableArray *)result depth:(NSUInteger)depth {
    if (self.error) return;
    if (depth > 16 || ++self.visited > 1500) {
        self.error = @"Notification Center has an unsupported Accessibility layout";
        return;
    }
    NSString *role = [self attribute:kAXRoleAttribute of:element];
    NSString *label = [self attribute:kAXDescriptionAttribute of:element];
    NSString *identifier = [self attribute:kAXIdentifierAttribute of:element];
    if ([role isEqual:@"AXButton"] && [label isEqual:@"Clear All"]) {
        [result insertObject:@{@"element": element, @"action": (__bridge NSString *)kAXPressAction,
            @"key": @"history-clear-all"} atIndex:0];
        return;
    }
    if ([role isEqual:@"AXGroup"]) {
        CFArrayRef names = NULL;
        AXError status = AXUIElementCopyActionNames(ax(element), &names);
        if (status == kAXErrorSuccess) {
            NSArray *actions = CFBridgingRelease(names);
            NSString *close = nil;
            for (NSString *action in actions) {
                CFStringRef description = NULL;
                AXError actionStatus = AXUIElementCopyActionDescription(ax(element), (__bridge CFStringRef)action, &description);
                NSString *text = CFBridgingRelease(description);
                if (actionStatus != kAXErrorSuccess) continue;
                if ([text isEqual:@"Clear All"]) { close = action; break; }
                if ([text isEqual:@"Close"]) close = action;
            }
            if (close) {
                NSString *key = identifier ?: [NSString stringWithFormat:@"%lu", (unsigned long)CFHash(ax(element))];
                [result addObject:@{@"element": element, @"action": close, @"key": key}];
                return;
            }
        } else if (status != kAXErrorInvalidUIElement && status != kAXErrorNotImplemented) {
            self.error = [NSString stringWithFormat:@"Accessibility could not read notification actions (error %d)", status];
            return;
        }
    }
    for (id child in [self attribute:kAXChildrenAttribute of:element]) {
        [self dismissals:child into:result depth:depth + 1];
    }
}
@end

static id application(NSString *identifier) {
    NSRunningApplication *app = [NSRunningApplication runningApplicationsWithBundleIdentifier:identifier].firstObject;
    return app ? CFBridgingRelease(AXUIElementCreateApplication(app.processIdentifier)) : nil;
}

static NSString *clearVisibleNotifications(void) {
    MNClearSession *session = [MNClearSession new];
    session.deadline = now() + 8;
    id center = application(@"com.apple.notificationcenterui");
    if (!center) return @"Notification Center is not running";
    BOOL wasOpen = [session panel:center] != nil;
    id clock = nil;
    BOOL opened = NO;
    if (!wasOpen && !session.error) {
        id controlCenter = application(@"com.apple.controlcenter");
        if (controlCenter) clock = [session find:@"com.apple.menuextra.clock" in:controlCenter depth:0];
        if (!clock) return session.error ?: @"could not find the menu-bar clock; this macOS Accessibility layout is unsupported";
        opened = [session perform:(__bridge NSString *)kAXPressAction on:clock];
    }

    // Window creation precedes history population. Waiting only for the window
    // can mistake a loading panel for an empty one (observed on macOS 26).
    NSTimeInterval openDeadline = now() + 2;
    id panel = nil;
    while (!session.error && !(panel = [session panel:center]) && now() < openDeadline) usleep(50000);
    if (!panel && !session.error) session.error = @"Notification Center did not open";
    if (opened && panel) usleep(600000);

    NSMutableSet *attempted = [NSMutableSet set];
    NSUInteger emptySnapshots = 0;
    while (!session.error) {
        panel = [session panel:center];
        if (!panel) {
            if (!session.error) session.error = @"Notification Center closed before clearing finished";
            break;
        }
        session.visited = 0;
        id list = [session find:@"AXNotificationListItems" in:panel depth:0];
        NSArray *children = list ? [session attribute:kAXChildrenAttribute of:list] : nil;
        if (!list || children.count == 0) {
            if (++emptySnapshots >= 3) break;
        } else {
            emptySnapshots = 0;
            NSMutableArray *dismissals = [NSMutableArray array];
            session.visited = 0;
            [session dismissals:list into:dismissals depth:0];
            if (!dismissals.count && !session.error) {
                session.error = @"could not find supported notification dismiss controls; the tested macOS UI language is English";
                break;
            }
            for (NSDictionary *dismissal in dismissals) {
                NSString *key = dismissal[@"key"];
                if ([attempted containsObject:key]) continue;
                [attempted addObject:key];
                [session perform:dismissal[@"action"] on:dismissal[@"element"]];
                // Re-read the tree after each action. Repeated AX success on a
                // disappearing proxy does not mean another notification cleared.
                break;
            }
        }
        usleep(150000);
    }

    if (opened) {
        MNClearSession *cleanup = [MNClearSession new];
        cleanup.deadline = now() + 2;
        if ([cleanup panel:center]) {
            [cleanup perform:(__bridge NSString *)kAXPressAction on:clock];
            while (!cleanup.error && [cleanup panel:center]) usleep(50000);
        }
        if (cleanup.error) {
            NSString *restoration = @"could not restore the closed Notification Center panel";
            session.error = session.error ? [NSString stringWithFormat:@"%@; %@", session.error, restoration] : restoration;
        }
    }
    // AXPress on the clock does not activate another app. Let macOS preserve
    // focus naturally; explicitly activating the original app would steal focus
    // back if the user switched applications during this operation.
    return session.error;
}

int mnClearNotifications(char **error) {
    @autoreleasepool {
        *error = NULL;
        if (!AXIsProcessTrustedWithOptions(NULL)) {
            // The system prompt names the actual responsible app, including
            // uncommon launchers that do not export terminal-identifying env vars.
            AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)@{
                (__bridge NSString *)kAXTrustedCheckOptionPrompt: @YES
            });
            return MNClearPermissionDenied;
        }
        AXUIElementRef system = AXUIElementCreateSystemWide();
        AXUIElementSetMessagingTimeout(system, 0.25);
        NSString *failure = clearVisibleNotifications();
        AXUIElementSetMessagingTimeout(system, 0);
        CFRelease(system);
        if (failure) {
            *error = strdup(failure.UTF8String);
            return MNClearFailed;
        }
        return MNClearOK;
    }
}

char *mnTerminalApplication(void) {
    @autoreleasepool {
        NSDictionary *environment = NSProcessInfo.processInfo.environment;
        NSString *identifier = environment[@"__CFBundleIdentifier"];
        if (identifier.length && ![identifier isEqual:@"com.nickhudkins.mac-notify"]) {
            NSURL *url = [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:identifier];
            NSBundle *bundle = url ? [NSBundle bundleWithURL:url] : nil;
            NSString *name = [bundle objectForInfoDictionaryKey:@"CFBundleDisplayName"] ?: [bundle objectForInfoDictionaryKey:@"CFBundleName"];
            if (name.length) return strdup(name.UTF8String);
        }
        NSDictionary *names = @{@"ghostty": @"Ghostty", @"Apple_Terminal": @"Terminal", @"iTerm.app": @"iTerm",
            @"kitty": @"kitty", @"WezTerm": @"WezTerm", @"vscode": @"Visual Studio Code", @"WarpTerminal": @"Warp"};
        NSString *name = names[environment[@"TERM_PROGRAM"] ?: @""];
        return name ? strdup(name.UTF8String) : NULL;
    }
}
