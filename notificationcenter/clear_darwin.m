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
- (BOOL)emptyHistory:(id)panel;
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
    self.error = [NSString stringWithFormat:@"Accessibility could not perform a Notification Center action (error %d)", status];
    return NO;
}

- (BOOL)emptyHistory:(id)panel {
    // On macOS 26 an empty history is an anonymous, childless AXGroup before
    // the widgets and footer controls. A missing list identifier alone could
    // instead mean loading or an incompatible layout, so verify this whole
    // observed empty-state shape. AXElementBusy is not exposed by this host.
    self.visited = 0;
    id editor = [self find:@"widget-editor-button" in:panel depth:0];
    id scroll = editor ? [self attribute:kAXParentAttribute of:editor] : nil;
    if (!scroll) return NO;
    if (![[self attribute:kAXRoleAttribute of:scroll] isEqual:@"AXScrollArea"]) return NO;
    NSArray *children = [self attribute:kAXChildrenAttribute of:scroll];
    if (children.count != 4 || ![children[2] isEqual:editor]) return NO;
    id history = children[0];
    if (![[self attribute:kAXRoleAttribute of:history] isEqual:@"AXGroup"] ||
        [self attribute:kAXIdentifierAttribute of:history] != nil ||
        ![[self attribute:kAXRoleAttribute of:children[1]] isEqual:@"AXOpaqueProviderGroup"] ||
        ![[self attribute:kAXIdentifierAttribute of:children[3]] isEqual:@"xmark"]) return NO;
    NSArray *items = [self attribute:kAXChildrenAttribute of:history];
    return items != nil && items.count == 0;
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
    BOOL openingAttempted = NO;
    BOOL observedPanel = wasOpen;
    if (!wasOpen && !session.error) {
        id controlCenter = application(@"com.apple.controlcenter");
        if (controlCenter) clock = [session find:@"com.apple.menuextra.clock" in:controlCenter depth:0];
        if (!clock) return session.error ?: @"could not find the menu-bar clock; this macOS Accessibility layout is unsupported";
        // AX actions may still execute after kAXErrorCannotComplete. Cleanup
        // must reconcile visibility after every attempt, not just an ACK.
        openingAttempted = YES;
        [session perform:(__bridge NSString *)kAXPressAction on:clock];
    }

    NSTimeInterval openDeadline = now() + 2;
    id panel = nil;
    while (!session.error && !(panel = [session panel:center]) && now() < openDeadline) usleep(50000);
    if (!panel && !session.error) session.error = @"Notification Center did not open";
    if (panel) observedPanel = YES;

    NSMutableSet *attempted = [NSMutableSet set];
    NSTimeInterval emptySince = 0;
    NSTimeInterval panelMissingSince = 0;
    while (!session.error) {
        panel = [session panel:center];
        if (!panel) {
            if (session.error) break;
            // Dismissing a group may briefly rebuild the identifying controls.
            // Retry that transition without treating disappearance as empty;
            // a panel that stays closed still cannot establish success.
            emptySince = 0;
            if (panelMissingSince == 0) panelMissingSince = now();
            if (now() - panelMissingSince >= .5) {
                session.error = @"Notification Center closed before clearing finished";
                break;
            }
            usleep(50000);
            continue;
        }
        panelMissingSince = 0;
        session.visited = 0;
        id list = [session find:@"AXNotificationListItems" in:panel depth:0];
        NSArray *children = list ? [session attribute:kAXChildrenAttribute of:list] : nil;
        BOOL knownEmpty = list ? children != nil && children.count == 0 : [session emptyHistory:panel];
        if (knownEmpty) {
            // The history host has no explicit readiness flag. Require a quiet
            // second in the recognized empty state so an opening/layout
            // transition cannot be accepted as a single empty snapshot.
            if (emptySince == 0) emptySince = now();
            if (now() - emptySince >= 1) break;
        } else if (!list) {
            emptySince = 0;
            // Unknown history remains unresolved until the operation deadline;
            // it must never be counted as empty or reported as success.
        } else {
            emptySince = 0;
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

    if (openingAttempted) {
        MNClearSession *cleanup = [MNClearSession new];
        cleanup.deadline = now() + 2;
        id visible = [cleanup panel:center];
        // A timed-out opening can arrive later. If no panel was ever observed,
        // spend the independent cleanup budget watching for that delayed open.
        // Otherwise allow a brief AX rebuild before assuming it is closed.
        NSTimeInterval visibilityDeadline = observedPanel ? MIN(cleanup.deadline, now() + .5) : cleanup.deadline;
        while (!cleanup.error && !visible && now() < visibilityDeadline) {
            usleep(50000);
            visible = [cleanup panel:center];
        }
        if (visible && !cleanup.error) {
            [cleanup perform:(__bridge NSString *)kAXPressAction on:clock];
            // A closing action timeout is ambiguous too: observed disappearance
            // confirms restoration even when the action acknowledgment failed.
            cleanup.error = nil;
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
        // The system-wide AX object sets a timeout for this client process,
        // rather than changing Notification Center or any global OS setting.
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
