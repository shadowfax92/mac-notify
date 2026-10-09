// Offline fixtures for the native controller at the public AX boundary.
// A virtual clock models delayed acknowledgments without sleeping or touching
// the desktop; only mnClearNotifications, the production C entrypoint, is tested.
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#include <unistd.h>
#include <stdio.h>

static NSTimeInterval tick;
static BOOL visible, hasNotification;
static NSTimeInterval pendingOpen;
static NSTimeInterval layoutReady;
static int presses;
static NSString *scenario;

@interface FixtureProcessInfo : NSObject
+ (instancetype)processInfo;
@property(readonly) NSTimeInterval systemUptime;
@property(readonly) NSDictionary *environment;
@end
@implementation FixtureProcessInfo
+ (instancetype)processInfo { return [self new]; }
- (NSTimeInterval)systemUptime { return tick; }
- (NSDictionary *)environment { return @{}; }
@end

@interface FixtureRunningApplication : NSObject
+ (NSArray *)runningApplicationsWithBundleIdentifier:(NSString *)identifier;
@property pid_t processIdentifier;
@end
@implementation FixtureRunningApplication
+ (NSArray *)runningApplicationsWithBundleIdentifier:(NSString *)identifier {
    FixtureRunningApplication *app = [self new];
    app.processIdentifier = [identifier isEqual:@"com.apple.controlcenter"] ? 2 : 1;
    return @[app];
}
@end

static int fixtureSleep(useconds_t microseconds) {
    tick += microseconds / 1000000.0;
    if (pendingOpen && tick >= pendingOpen) { visible = YES; pendingOpen = 0; }
    return 0;
}
static Boolean fixtureTrusted(CFDictionaryRef options) { return true; }
static AXUIElementRef fixtureApplication(pid_t pid) {
    return (AXUIElementRef)CFBridgingRetain(pid == 1 ? @"center" : @"control");
}
static AXUIElementRef fixtureSystem(void) { return (AXUIElementRef)CFBridgingRetain(@"system"); }
static AXError fixtureTimeout(AXUIElementRef element, float timeout) { return kAXErrorSuccess; }

static AXError fixtureAttribute(AXUIElementRef element, CFStringRef attribute, CFTypeRef *result) {
    NSString *node = (__bridge NSString *)element;
    if (!node) return kAXErrorInvalidUIElement;
    NSDictionary *attributes = nil;
    if ([node isEqual:@"center"]) attributes = @{@"AXRole": @"AXApplication", @"AXWindows": visible ? @[@"panel"] : @[]};
    if ([node isEqual:@"control"]) attributes = @{@"AXRole": @"AXApplication", @"AXChildren": @[@"clock"]};
    if ([node isEqual:@"clock"]) attributes = @{@"AXRole": @"AXMenuBarItem", @"AXIdentifier": @"com.apple.menuextra.clock", @"AXChildren": @[]};
    if ([node isEqual:@"panel"]) attributes = @{@"AXRole": @"AXWindow", @"AXSubrole": @"AXSystemDialog", @"AXChildren": @[@"scroll"]};
    if ([node isEqual:@"scroll"]) attributes = @{@"AXRole": @"AXScrollArea", @"AXChildren": tick < layoutReady ? @[@"history", @"widgets", @"xmark"] : @[@"history", @"widgets", @"editor", @"xmark"]};
    if ([node isEqual:@"history"]) {
        NSMutableDictionary *history = [@{@"AXRole": @"AXGroup", @"AXChildren": hasNotification ? @[@"notification"] : @[]} mutableCopy];
        if ([scenario isEqual:@"unknown-history"]) history[@"AXIdentifier"] = @"renamed-history";
        else if (hasNotification) history[@"AXIdentifier"] = @"AXNotificationListItems";
        attributes = history;
    }
    if ([node isEqual:@"widgets"]) attributes = @{@"AXRole": @"AXOpaqueProviderGroup", @"AXChildren": @[]};
    if ([node isEqual:@"editor"]) attributes = @{@"AXRole": @"AXButton", @"AXIdentifier": @"widget-editor-button", @"AXParent": @"scroll", @"AXChildren": @[]};
    if ([node isEqual:@"xmark"]) attributes = @{@"AXRole": @"AXMenuButton", @"AXIdentifier": @"xmark", @"AXChildren": @[]};
    if ([node isEqual:@"notification"]) attributes = @{@"AXRole": @"AXGroup", @"AXIdentifier": @"notification-1", @"AXChildren": @[]};
    id value = attributes[(__bridge NSString *)attribute];
    *result = value ? CFBridgingRetain(value) : NULL;
    return value ? kAXErrorSuccess : kAXErrorNoValue;
}
static AXError fixtureActions(AXUIElementRef element, CFArrayRef *actions) {
    *actions = (CFArrayRef)CFBridgingRetain([(__bridge NSString *)element isEqual:@"notification"] ? @[@"fixture-close"] : @[]);
    return kAXErrorSuccess;
}
static AXError fixtureActionDescription(AXUIElementRef element, CFStringRef action, CFStringRef *description) {
    *description = (CFStringRef)CFBridgingRetain(@"Close");
    return kAXErrorSuccess;
}
static AXError fixturePerform(AXUIElementRef element, CFStringRef action) {
    NSString *node = (__bridge NSString *)element;
    if ([node isEqual:@"notification"]) {
        hasNotification = NO;
        // Dismissal can briefly rebuild the panel's AX subtree. A permanently
        // closed panel must still fail rather than imply an empty history.
        if ([scenario isEqual:@"transient-panel"]) layoutReady = tick + .3;
        if ([scenario isEqual:@"closed-panel"]) visible = NO;
        return kAXErrorSuccess;
    }
    if (![node isEqual:@"clock"]) return kAXErrorActionUnsupported;
    presses++;
    if (!visible && [scenario isEqual:@"opening-timeout"]) {
        pendingOpen = tick + .7;
        return kAXErrorCannotComplete;
    }
    BOOL closing = visible;
    visible = !visible;
    return closing && [scenario isEqual:@"closing-timeout"] ? kAXErrorCannotComplete : kAXErrorSuccess;
}

#define NSProcessInfo FixtureProcessInfo
#define NSRunningApplication FixtureRunningApplication
#define usleep fixtureSleep
#define AXIsProcessTrustedWithOptions fixtureTrusted
#define AXUIElementCreateApplication fixtureApplication
#define AXUIElementCreateSystemWide fixtureSystem
#define AXUIElementSetMessagingTimeout fixtureTimeout
#define AXUIElementCopyAttributeValue fixtureAttribute
#define AXUIElementCopyActionNames fixtureActions
#define AXUIElementCopyActionDescription fixtureActionDescription
#define AXUIElementPerformAction fixturePerform
#include "../clear_darwin.m"

int main(void) {
    @autoreleasepool {
        int failures = 0;
        for (NSString *test in @[@"empty", @"dismiss", @"unknown-history", @"opening-timeout", @"closing-timeout", @"transient-panel", @"closed-panel"]) {
            scenario = test; tick = 100; visible = NO; presses = 0; pendingOpen = 0; layoutReady = 0;
            hasNotification = [test isEqual:@"dismiss"] || [test isEqual:@"unknown-history"] || [test isEqual:@"transient-panel"] || [test isEqual:@"closed-panel"];
            char *error = NULL;
            int status = mnClearNotifications(&error);
            BOOL wantError = [test isEqual:@"unknown-history"] || [test isEqual:@"opening-timeout"] || [test isEqual:@"closed-panel"];
            BOOL pass = (status != MNClearOK) == wantError && !visible && !pendingOpen && presses == ([test isEqual:@"closed-panel"] ? 1 : 2);
            if ([test isEqual:@"dismiss"]) pass = pass && !hasNotification;
            if ([test isEqual:@"unknown-history"]) pass = pass && hasNotification;
            if (tick - 100 > 10) pass = NO;
            printf("%s: %s status=%d seconds=%.2f clock_presses=%d panel_open=%d pending_open=%d error=%s\n",
                test.UTF8String, pass ? "PASS" : "FAIL", status, tick - 100, presses, visible,
                pendingOpen != 0, error ?: "none");
            if (!pass) failures++;
            free(error);
        }
        return failures ? 1 : 0;
    }
}
