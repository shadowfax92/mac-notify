#import <UserNotifications/UserNotifications.h>
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

// --- Notification Delegate ---

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

// --- Overlay Window ---

static NSPanel *_overlayPanel = nil;
static int _overlayGeneration = 0;

static void pulseGlow(CALayer *layer, int generation) {
    if (_overlayPanel == nil || _overlayGeneration != generation) return;

    BOOL expand = (layer.shadowRadius < 15);
    CGFloat targetRadius = expand ? 20 : 8;
    float targetOpacity = expand ? 0.9 : 0.4;

    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
        ctx.duration = 1.0;
        ctx.allowsImplicitAnimation = YES;
        layer.shadowRadius = targetRadius;
        layer.shadowOpacity = targetOpacity;
    } completionHandler:^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            pulseGlow(layer, generation);
        });
    }];
}

void showOverlayNotification(const char *title, const char *body, double timeout) {
    char *titleCopy = strdup(title);
    char *bodyCopy = strdup(body);

    dispatch_async(dispatch_get_main_queue(), ^{
        if (_overlayPanel) {
            [_overlayPanel close];
            [_overlayPanel release];
            _overlayPanel = nil;
        }
        _overlayGeneration++;
        int gen = _overlayGeneration;

        NSString *titleStr = [NSString stringWithUTF8String:titleCopy];
        NSString *bodyStr = [NSString stringWithUTF8String:bodyCopy];
        free(titleCopy);
        free(bodyCopy);

        CGFloat width = 400;
        CGFloat pad = 20;
        CGFloat contentWidth = width - pad * 2;
        CGFloat titleHeight = 20;
        CGFloat titleTopPad = 14;
        CGFloat bodyTopPad = 6;
        CGFloat bodyBottomPad = 14;
        CGFloat maxBodyHeight = 180;

        // Measure body text height using NSTextStorage for accurate wrapping
        NSFont *bodyFont = [NSFont systemFontOfSize:14 weight:NSFontWeightSemibold];
        NSTextStorage *textStorage = [[NSTextStorage alloc] initWithString:bodyStr
                                                               attributes:@{NSFontAttributeName: bodyFont}];
        NSTextContainer *textContainer = [[NSTextContainer alloc] initWithSize:NSMakeSize(contentWidth, CGFLOAT_MAX)];
        NSLayoutManager *layoutManager = [[NSLayoutManager alloc] init];
        textContainer.lineFragmentPadding = 0;
        textContainer.lineBreakMode = NSLineBreakByCharWrapping;
        [layoutManager addTextContainer:textContainer];
        [textStorage addLayoutManager:layoutManager];
        [layoutManager glyphRangeForTextContainer:textContainer];
        CGFloat bodyHeight = ceil([layoutManager usedRectForTextContainer:textContainer].size.height);
        [textStorage release];
        [textContainer release];
        [layoutManager release];
        if (bodyHeight < 20) bodyHeight = 20;
        if (bodyHeight > maxBodyHeight) bodyHeight = maxBodyHeight;

        CGFloat height = titleTopPad + titleHeight + bodyTopPad + bodyHeight + bodyBottomPad;

        NSScreen *screen = [NSScreen mainScreen];
        NSRect visibleFrame = screen.visibleFrame;
        CGFloat x = NSMidX(visibleFrame) - width / 2;
        CGFloat y = NSMaxY(visibleFrame) - height - 8;

        NSRect frame = NSMakeRect(x, y, width, height);
        _overlayPanel = [[NSPanel alloc]
            initWithContentRect:frame
            styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
            backing:NSBackingStoreBuffered
            defer:NO];

        _overlayPanel.level = NSStatusWindowLevel + 1;
        _overlayPanel.opaque = NO;
        _overlayPanel.backgroundColor = [NSColor clearColor];
        _overlayPanel.hasShadow = NO;
        _overlayPanel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces |
                                           NSWindowCollectionBehaviorStationary |
                                           NSWindowCollectionBehaviorFullScreenAuxiliary;
        _overlayPanel.ignoresMouseEvents = YES;
        _overlayPanel.hidesOnDeactivate = NO;

        NSView *contentView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, width, height)];
        contentView.wantsLayer = YES;
        contentView.layer.cornerRadius = 12;
        contentView.layer.backgroundColor = [[NSColor colorWithWhite:0.08 alpha:0.95] CGColor];
        contentView.layer.borderColor = [[NSColor colorWithRed:0 green:0.85 blue:1.0 alpha:0.6] CGColor];
        contentView.layer.borderWidth = 1.5;
        contentView.layer.shadowColor = [[NSColor colorWithRed:0 green:0.85 blue:1.0 alpha:1.0] CGColor];
        contentView.layer.shadowRadius = 8;
        contentView.layer.shadowOpacity = 0.4;
        contentView.layer.shadowOffset = CGSizeMake(0, 0);

        NSTextField *titleLabel = [NSTextField labelWithString:titleStr];
        titleLabel.font = [NSFont systemFontOfSize:11 weight:NSFontWeightMedium];
        titleLabel.textColor = [NSColor colorWithWhite:0.55 alpha:1.0];
        titleLabel.frame = NSMakeRect(pad, height - titleTopPad - titleHeight, contentWidth, titleHeight);
        titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [contentView addSubview:titleLabel];

        NSTextView *bodyText = [[NSTextView alloc] initWithFrame:NSMakeRect(pad, bodyBottomPad, contentWidth, bodyHeight)];
        [bodyText setString:bodyStr];
        bodyText.font = bodyFont;
        bodyText.textColor = [NSColor whiteColor];
        bodyText.backgroundColor = [NSColor clearColor];
        bodyText.drawsBackground = NO;
        bodyText.editable = NO;
        bodyText.selectable = NO;
        bodyText.horizontallyResizable = NO;
        bodyText.verticallyResizable = NO;
        bodyText.textContainerInset = NSMakeSize(0, 0);
        bodyText.textContainer.lineBreakMode = NSLineBreakByCharWrapping;
        bodyText.textContainer.widthTracksTextView = YES;
        [contentView addSubview:bodyText];
        [bodyText release];

        _overlayPanel.contentView = contentView;

        // Fade in
        _overlayPanel.alphaValue = 0;
        [_overlayPanel orderFront:nil];
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
            ctx.duration = 0.3;
            _overlayPanel.animator.alphaValue = 1.0;
        }];

        // Start glow pulse
        pulseGlow(contentView.layer, gen);

        // Auto-dismiss
        double fadeStart = (timeout > 0.5) ? timeout - 0.5 : timeout;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(fadeStart * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (_overlayGeneration == gen && _overlayPanel) {
                [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
                    ctx.duration = 0.5;
                    _overlayPanel.animator.alphaValue = 0;
                } completionHandler:^{
                    if (_overlayGeneration == gen && _overlayPanel) {
                        [_overlayPanel close];
                        [_overlayPanel release];
                        _overlayPanel = nil;
                    }
                }];
            }
        });
    });
}
