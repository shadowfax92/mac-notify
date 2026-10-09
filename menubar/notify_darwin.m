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
    // Runtime enablement can arrive on the config watcher, outside AppKit's
    // main-thread autorelease pool. Go serializes setup before enabled sends.
    @autoreleasepool {
        _delegate = [[NotifyDelegate alloc] init];
        [[UNUserNotificationCenter currentNotificationCenter] setDelegate:_delegate];
    }
}

void requestNotificationAuth(void) {
    @autoreleasepool {
        UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
        [center requestAuthorizationWithOptions:(UNAuthorizationOptionAlert | UNAuthorizationOptionSound | UNAuthorizationOptionBadge)
                             completionHandler:^(BOOL granted, NSError *error) {
            if (error) {
                NSLog(@"mac-notify: auth error: %@", error);
            }
        }];
    }
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

// These run in the bundled daemon, whose notification center owns the requests.
// Cancel pending requests too so they cannot appear after dismissal. The local
// pools also cover calls from IPC goroutines without a Cocoa autorelease pool.
void clearDarwinNotifications(void) {
    @autoreleasepool {
        UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
        [center removeAllPendingNotificationRequests];
        [center removeAllDeliveredNotifications];
    }
}

void removeDarwinNotification(const char *identifier) {
    @autoreleasepool {
        NSString *ident = [NSString stringWithUTF8String:identifier];
        NSArray *identifiers = @[ident];
        UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
        [center removePendingNotificationRequestsWithIdentifiers:identifiers];
        [center removeDeliveredNotificationsWithIdentifiers:identifiers];
    }
}

// --- Terminal look ---
//
// The overlay and the blockers share one visual language ("02 Terminal" in
// the design file): an always-dark, hard-cornered SF Mono slab. It is
// deliberately unlike the focus app's pill (clear glass capsule, amber glow),
// so the two read apart at a glance even though both can sit at the
// top-center of the screen.
//
// The helpers below only build and animate views. Where a panel sits, and how
// blockers stack, stays with showOverlayNotification and reflowBlockers. All
// of them run on the main thread, and the file is compiled without ARC, so
// every alloc is paired with a release.

// Today's panel width. Any wider and a top-center overlay would touch the
// top-right blocker stack on 1280pt-wide screens.
static const CGFloat kTermWidth = 400;
static const CGFloat kTermInset = 16;            // left/right text inset
static const CGFloat kTermLineHeight = 21;       // fixed body line box
static const NSUInteger kTermMaxBodyLines = 8;   // roughly the old 180pt body cap
static const NSUInteger kTermTypeTicks = 40;     // 40 ticks x 10ms = 0.4s to type any body
static const double kTermTypeTick = 0.010;

static NSColor *termColor(unsigned rgb, CGFloat alpha) {
    return [NSColor colorWithSRGBRed:((rgb >> 16) & 0xFF) / 255.0
                               green:((rgb >> 8) & 0xFF) / 255.0
                                blue:(rgb & 0xFF) / 255.0
                               alpha:alpha];
}

// Lays rows out top-down, so each row's position does not depend on the
// panel's final height (AppKit's default origin is bottom-left).
@interface TermCanvas : NSView
@end

@implementation TermCanvas
- (BOOL)isFlipped { return YES; }
@end

// Styled body text. Lines wrap at words (a word longer than a line breaks by
// character) in a fixed 21pt line box. A typed prefix never needs more lines
// than the full body, so the panel is sized once up front; a half-typed word
// at a line end may hop down a line while it types, as in any editor.
static NSAttributedString *termBody(NSString *text, NSColor *textColor) {
    NSFont *font = [NSFont monospacedSystemFontOfSize:14 weight:NSFontWeightRegular];
    NSMutableParagraphStyle *para = [[NSMutableParagraphStyle alloc] init];
    para.minimumLineHeight = kTermLineHeight;
    para.maximumLineHeight = kTermLineHeight;
    para.lineBreakMode = NSLineBreakByWordWrapping;
    // TextKit puts a fixed line box's spare height above the glyphs; lift them
    // by half of it so each line is vertically centred in its box.
    CGFloat natural = font.ascender - font.descender + font.leading;
    CGFloat lift = floor((kTermLineHeight - natural) / 2);
    NSDictionary *attrs = @{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: textColor,
        NSParagraphStyleAttributeName: para,
        NSBaselineOffsetAttributeName: @(lift),
    };
    NSAttributedString *s = [[NSAttributedString alloc] initWithString:text attributes:attrs];
    [para release];
    return [s autorelease];
}

// Lays the body out at the panel's text width, the same way makeTermBodyView
// will, and returns its line count (at least 1, so an empty body keeps one
// line of height). *lastFit receives the index just past the last character
// on line kTermMaxBodyLines, or the text's length when everything fits.
static NSUInteger termLayoutBody(NSString *text, NSUInteger *lastFit) {
    NSTextStorage *storage = [[NSTextStorage alloc] initWithAttributedString:
        termBody(text, [NSColor whiteColor])];
    NSTextContainer *container = [[NSTextContainer alloc] initWithSize:NSMakeSize(kTermWidth - 2 * kTermInset, CGFLOAT_MAX)];
    NSLayoutManager *layout = [[NSLayoutManager alloc] init];
    container.lineFragmentPadding = 0;
    [layout addTextContainer:container];
    [storage addLayoutManager:layout];
    __block NSUInteger lines = 0;
    __block NSUInteger fit = text.length;
    [layout enumerateLineFragmentsForGlyphRange:[layout glyphRangeForTextContainer:container]
                                     usingBlock:^(NSRect rect, NSRect usedRect, NSTextContainer *tc,
                                                  NSRange glyphRange, BOOL *stop) {
        lines++;
        if (lines == kTermMaxBodyLines) {
            fit = NSMaxRange([layout characterRangeForGlyphRange:glyphRange actualGlyphRange:NULL]);
        }
    }];
    [storage release];
    [container release];
    [layout release];
    if (lastFit) *lastFit = fit;
    return lines < 1 ? 1 : lines;
}

// Fits the body into kTermMaxBodyLines and returns its height. Longer text is
// cut at a composed-character boundary and ends in "…", so the reader can see
// it was cut rather than clipped with the overflow. *fitted receives the text
// to display.
static CGFloat termFitBody(NSString *text, NSString **fitted) {
    NSUInteger cut = 0;
    NSUInteger lines = termLayoutBody(text, &cut);
    if (lines <= kTermMaxBodyLines) {
        *fitted = text;
        return lines * kTermLineHeight;
    }
    // Start from the end of the last line that fits and give back a composed
    // character at a time until the cut text and "…" fit. On a full last line
    // that can take a few steps: "…" glues onto the cut word, so the word has
    // to shrink until word and "…" fit on the line together, and wide glyphs
    // (emoji, CJK) need more room.
    NSString *candidate = @"…";
    while (cut > 0) {
        cut = [text rangeOfComposedCharacterSequenceAtIndex:cut - 1].location;
        candidate = [[text substringToIndex:cut] stringByAppendingString:@"…"];
        if (termLayoutBody(candidate, NULL) <= kTermMaxBodyLines) break;
    }
    *fitted = candidate;
    return kTermMaxBodyLines * kTermLineHeight;
}

// A non-editable text view for the body, laid out exactly like the measurement
// above (no container padding or inset). It must be TextKit 1: a default
// NSTextView uses TextKit 2, which can wrap the same string onto a different
// number of lines than the NSLayoutManager in termLayoutBody, spilling the
// last line into the padding. Returns an autoreleased view.
static NSTextView *makeTermBodyView(NSRect frame, NSAttributedString *initial) {
    NSTextView *view = [NSTextView textViewUsingTextLayoutManager:NO];
    view.frame = frame;
    view.drawsBackground = NO;
    view.editable = NO;
    view.selectable = NO;
    view.horizontallyResizable = NO;
    view.verticallyResizable = NO;
    view.textContainerInset = NSZeroSize;
    view.textContainer.lineFragmentPadding = 0;
    view.textContainer.widthTracksTextView = YES;
    [view.textStorage setAttributedString:initial];
    return view;
}

// A one-line header label. Callers size rows from fittingSize, so line breaks
// in the text (a --source can contain them) are flattened to spaces first;
// otherwise the label would grow downward over the body.
static NSTextField *termLabel(NSString *text, CGFloat size, NSFontWeight weight, NSColor *color) {
    NSString *oneLine = [[text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]
                         componentsJoinedByString:@" "];
    NSTextField *label = [NSTextField labelWithString:oneLine];
    label.font = [NSFont monospacedSystemFontOfSize:size weight:weight];
    label.textColor = color;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    label.maximumNumberOfLines = 1;
    return label;
}

// Rounded-rect mask for the blur. NSVisualEffectView ignores layer corner
// radii when blending behind the window, so the shape has to come from a
// stretchable mask image; the window shadow follows the same shape.
static NSImage *termCornerMask(CGFloat radius) {
    CGFloat edge = radius * 2 + 1;
    NSImage *mask = [NSImage imageWithSize:NSMakeSize(edge, edge) flipped:NO drawingHandler:^BOOL(NSRect rect) {
        [[NSColor blackColor] setFill];
        [[NSBezierPath bezierPathWithRoundedRect:rect xRadius:radius yRadius:radius] fill];
        return YES;
    }];
    mask.capInsets = NSEdgeInsetsMake(radius, radius, radius, radius);
    mask.resizingMode = NSImageResizingModeStretch;
    return mask;
}

// The slab: dark HUD blur with the tinted fill and 1pt rim on top. Returns the
// panel's content view (+1); *canvasOut receives the top-down view to lay rows
// out in (owned by the returned view).
static NSVisualEffectView *makeTermSurface(NSSize size, NSColor *fill, NSColor *rim, TermCanvas **canvasOut) {
    NSRect bounds = NSMakeRect(0, 0, size.width, size.height);
    NSVisualEffectView *surface = [[NSVisualEffectView alloc] initWithFrame:bounds];
    surface.material = NSVisualEffectMaterialHUDWindow;
    surface.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    // These panels never become key; "follows window" would draw the blur as
    // permanently inactive.
    surface.state = NSVisualEffectStateActive;
    surface.maskImage = termCornerMask(4);

    TermCanvas *canvas = [[TermCanvas alloc] initWithFrame:bounds];
    canvas.wantsLayer = YES;
    canvas.layer.backgroundColor = fill.CGColor;
    canvas.layer.cornerRadius = 4;
    canvas.layer.masksToBounds = YES;
    // A layer border draws above sublayers, so the rim also edges the
    // blocker's red strip.
    canvas.layer.borderColor = rim.CGColor;
    canvas.layer.borderWidth = 1;
    [surface addSubview:canvas];
    [canvas release];
    *canvasOut = canvas;
    return surface;
}

// Borderless, non-activating panel above the menu bar on every Space. Pinned
// to dark so the slab looks the same whatever the system appearance. The
// window shadow replaces the old layer glow: a layer shadow on the content
// view would be clipped at the window's edge. Returns +1 (NSPanel defaults to
// releasedWhenClosed = NO, so callers close and then release).
static NSPanel *makeTermPanel(NSRect frame) {
    NSPanel *panel = [[NSPanel alloc]
        initWithContentRect:frame
        styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
        backing:NSBackingStoreBuffered
        defer:NO];
    panel.level = NSStatusWindowLevel + 1;
    panel.opaque = NO;
    panel.backgroundColor = [NSColor clearColor];
    panel.hasShadow = YES;
    panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces |
                               NSWindowCollectionBehaviorStationary |
                               NSWindowCollectionBehaviorFullScreenAuxiliary;
    panel.hidesOnDeactivate = NO;
    panel.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    return panel;
}

// Types the body in, a few characters per 10ms tick, so any length finishes
// within kTermTypeTicks ticks (0.4s) and long messages keep the full
// overlay_timeout on screen. Stops early once alive() turns false: the overlay
// ties it to its panel and generation, so a replaced or dismissed overlay is
// never typed into. Each scheduled tick retains the text view until it runs.
static void typeBody(NSTextView *body, NSString *text, NSColor *textColor,
                     NSUInteger shown, BOOL (^alive)(void)) {
    if (!alive()) return;
    NSUInteger total = text.length;
    NSUInteger step = (total + kTermTypeTicks - 1) / kTermTypeTicks;
    if (step < 1) step = 1;
    shown += step;
    if (shown < total) {
        // Never split a surrogate pair or a composed character mid-glyph.
        shown = NSMaxRange([text rangeOfComposedCharacterSequenceAtIndex:shown - 1]);
    }
    if (shown > total) shown = total;
    [body.textStorage setAttributedString:termBody([text substringToIndex:shown], textColor)];
    if (shown >= total) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kTermTypeTick * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        typeBody(body, text, textColor, shown, alive);
    });
}

static NSString *termTimestamp(void) {
    static NSDateFormatter *formatter = nil;
    if (formatter == nil) {
        formatter = [[NSDateFormatter alloc] init];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.dateFormat = @"HH:mm:ss";
    }
    return [formatter stringFromDate:[NSDate date]];
}

// The blocker's close mark: an 8pt ✕ drawn as two strokes.
static NSImage *termCloseGlyph(NSColor *color) {
    return [NSImage imageWithSize:NSMakeSize(8, 8) flipped:NO drawingHandler:^BOOL(NSRect rect) {
        NSBezierPath *path = [NSBezierPath bezierPath];
        [path moveToPoint:NSMakePoint(1, 1)];
        [path lineToPoint:NSMakePoint(7, 7)];
        [path moveToPoint:NSMakePoint(7, 1)];
        [path lineToPoint:NSMakePoint(1, 7)];
        path.lineWidth = 1.7;
        path.lineCapStyle = NSLineCapStyleSquare;
        [color setStroke];
        [path stroke];
        return YES;
    }];
}

// --- Overlay Window ---

static NSPanel *_overlayPanel = nil;
static int _overlayGeneration = 0;

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

        CGFloat headerTop = 12;
        CGFloat headerHeight = 18;
        CGFloat bodyTop = headerTop + headerHeight + 8;
        CGFloat bottomPad = 14;
        NSString *shownBody = nil;
        CGFloat bodyHeight = termFitBody(bodyStr, &shownBody);
        CGFloat height = bodyTop + bodyHeight + bottomPad;

        // Today's slot: centred, 8pt under the menu bar.
        NSScreen *screen = [NSScreen mainScreen];
        NSRect visibleFrame = screen.visibleFrame;
        CGFloat x = NSMidX(visibleFrame) - kTermWidth / 2;
        CGFloat y = NSMaxY(visibleFrame) - height - 8;

        _overlayPanel = makeTermPanel(NSMakeRect(x, y, kTermWidth, height));
        _overlayPanel.ignoresMouseEvents = YES;

        NSColor *green = termColor(0x4DFF88, 1.0);
        NSColor *bodyColor = termColor(0xE9F5EC, 1.0);
        TermCanvas *canvas = nil;
        NSVisualEffectView *surface = makeTermSurface(NSMakeSize(kTermWidth, height),
                                                      termColor(0x060908, 0.91),
                                                      termColor(0x4DFF88, 0.35), &canvas);

        // Header: send time on the right, source as an inverse-video tag on the
        // left, truncated so it never runs into the time.
        NSTextField *timeLabel = termLabel(termTimestamp(), 11, NSFontWeightRegular, termColor(0x4DFF88, 0.5));
        NSSize timeSize = timeLabel.fittingSize;
        // Labels pad their text by 2pt per side; offset so the glyphs, not the
        // label frames, line up with the 16pt inset.
        timeLabel.frame = NSMakeRect(kTermWidth - kTermInset + 2 - timeSize.width,
                                     headerTop + (headerHeight - timeSize.height) / 2,
                                     timeSize.width, timeSize.height);
        [canvas addSubview:timeLabel];

        NSTextField *sourceLabel = termLabel(titleStr, 11.5, NSFontWeightBold, termColor(0x04140A, 1.0));
        NSSize sourceSize = sourceLabel.fittingSize;
        CGFloat tagWidth = MIN(sourceSize.width + 8, NSMinX(timeLabel.frame) - 12 - kTermInset);
        NSView *tag = [[NSView alloc] initWithFrame:NSMakeRect(kTermInset, headerTop, tagWidth, headerHeight)];
        tag.wantsLayer = YES;
        tag.layer.backgroundColor = green.CGColor;
        tag.layer.cornerRadius = 2;
        sourceLabel.frame = NSMakeRect(4, (headerHeight - sourceSize.height) / 2, tagWidth - 8, sourceSize.height);
        [tag addSubview:sourceLabel];
        [canvas addSubview:tag];
        [tag release];

        // Body starts empty and types in below.
        NSTextView *bodyView = makeTermBodyView(NSMakeRect(kTermInset, bodyTop, kTermWidth - 2 * kTermInset, bodyHeight),
                                                termBody(@"", bodyColor));
        [canvas addSubview:bodyView];

        _overlayPanel.contentView = surface;
        [surface release];

        // Fade in
        _overlayPanel.alphaValue = 0;
        [_overlayPanel orderFront:nil];
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
            ctx.duration = 0.3;
            _overlayPanel.animator.alphaValue = 1.0;
        }];

        // Type the body in, stopping if this overlay is replaced or dismissed
        // first.
        typeBody(bodyView, shownBody, bodyColor, 0, ^BOOL(void) {
            return _overlayPanel != nil && _overlayGeneration == gen;
        });

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

// --- Blocker Windows ---
//
// Persistent variants of the overlay: the same terminal slab with a red
// "■ BLOCKED" header strip, stacked vertically down the right edge. Each stays
// on screen until the user clicks its ✕ (or `clear` dismisses the whole
// stack). A new --blocker send takes the top slot and the existing stack
// slides down; closing one lets the panels below slide back up. Unlike the
// overlay they accept mouse events for the close button; the nonactivating
// panel style keeps those clicks from stealing focus from the frontmost app.

static NSMutableArray *_blockerOrder = nil;        // NSNumber tokens, index 0 = top (newest)
static NSMutableDictionary *_blockerPanels = nil;  // token -> NSPanel
static NSInteger _blockerNextToken = 0;

// Reposition every blocker: index 0 hugs the menu bar, the rest hang below it
// in stack order. Animated, so additions/removals slide. Main thread only.
static void reflowBlockers(void) {
    NSScreen *screen = [NSScreen mainScreen];
    NSRect visibleFrame = screen.visibleFrame;
    CGFloat margin = 16;
    CGFloat gap = 12;
    CGFloat y = NSMaxY(visibleFrame) - 8;
    for (NSNumber *tok in _blockerOrder) {
        NSPanel *panel = [_blockerPanels objectForKey:tok];
        if (panel == nil) continue;
        NSRect f = panel.frame;
        f.origin.x = NSMaxX(visibleFrame) - f.size.width - margin;
        y -= f.size.height;
        f.origin.y = y;
        y -= gap;
        [panel.animator setFrame:f display:YES];
    }
}

// Fade out and tear down one blocker. Removing its token from the registry
// first takes it out of the reflow and makes a repeat close (a second ✕ click
// or a `clear` during the fade) a no-op, so the panel is released only once.
// The completion block retains the panel through the fade, then releases the
// final alloc reference. Main thread only.
static void closeBlocker(NSNumber *tok) {
    NSPanel *panel = [_blockerPanels objectForKey:tok];
    if (panel == nil) return;
    [_blockerPanels removeObjectForKey:tok];
    [_blockerOrder removeObject:tok];
    reflowBlockers();
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
        ctx.duration = 0.25;
        panel.animator.alphaValue = 0;
    } completionHandler:^{
        [panel close];
        [panel release];
    }];
}

static void closeAllBlockers(void) {
    NSArray *toks = [NSArray arrayWithArray:_blockerOrder];
    for (NSNumber *tok in toks) {
        closeBlocker(tok);
    }
}

@interface BlockerController : NSObject
- (void)dismiss:(id)sender;
@end

@implementation BlockerController
- (void)dismiss:(id)sender {
    closeBlocker([NSNumber numberWithInteger:((NSView *)sender).tag]);
}
@end

// Long-lived target for the close button's action; one instance per process.
static BlockerController *_blockerController = nil;

void dismissBlocker(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        closeAllBlockers();
    });
}

void showBlockerNotification(const char *title, const char *body) {
    char *titleCopy = strdup(title);
    char *bodyCopy = strdup(body);

    dispatch_async(dispatch_get_main_queue(), ^{
        if (_blockerOrder == nil) {
            _blockerOrder = [[NSMutableArray alloc] init];
            _blockerPanels = [[NSMutableDictionary alloc] init];
        }
        if (_blockerController == nil) {
            _blockerController = [[BlockerController alloc] init];
        }

        NSString *titleStr = [NSString stringWithUTF8String:titleCopy];
        NSString *bodyStr = [NSString stringWithUTF8String:bodyCopy];
        free(titleCopy);
        free(bodyCopy);

        CGFloat stripHeight = 26;
        CGFloat bodyTop = stripHeight + 11;
        CGFloat bottomPad = 14;
        CGFloat closeSize = 20;
        NSString *shownBody = nil;
        CGFloat bodyHeight = termFitBody(bodyStr, &shownBody);
        CGFloat height = bodyTop + bodyHeight + bottomPad;

        // Provisional frame in the top slot; reflowBlockers below places it.
        NSScreen *screen = [NSScreen mainScreen];
        NSRect visibleFrame = screen.visibleFrame;
        CGFloat margin = 16;
        CGFloat x = NSMaxX(visibleFrame) - kTermWidth - margin;
        CGFloat y = NSMaxY(visibleFrame) - height - 8;
        NSPanel *panel = makeTermPanel(NSMakeRect(x, y, kTermWidth, height));

        // The blocked red: one notch softer than a pure alarm red so it does
        // not glare for as long as a blocker stays up, yet still reads as
        // "blocked". It colors the strip and, dimmed, the rim.
        NSColor *red = termColor(0xE04A3F, 1.0);
        NSColor *ink = termColor(0x140202, 1.0);
        TermCanvas *canvas = nil;
        NSVisualEffectView *surface = makeTermSurface(NSMakeSize(kTermWidth, height),
                                                      termColor(0x0A0606, 0.92),
                                                      termColor(0xE5574F, 0.5), &canvas);

        // Header strip: "■ BLOCKED", the source, and the close box.
        NSView *strip = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, kTermWidth, stripHeight)];
        strip.wantsLayer = YES;
        strip.layer.backgroundColor = red.CGColor;
        [canvas addSubview:strip];
        [strip release];

        NSRect closeFrame = NSMakeRect(kTermWidth - 6 - closeSize, (stripHeight - closeSize) / 2, closeSize, closeSize);
        NSView *closeBox = [[NSView alloc] initWithFrame:closeFrame];
        closeBox.wantsLayer = YES;
        closeBox.layer.backgroundColor = [ink colorWithAlphaComponent:0.15].CGColor;
        closeBox.layer.cornerRadius = 2;
        [canvas addSubview:closeBox];
        [closeBox release];

        NSTextField *flagLabel = termLabel(@"■ BLOCKED", 11.5, NSFontWeightBold, ink);
        NSSize flagSize = flagLabel.fittingSize;
        flagLabel.frame = NSMakeRect(kTermInset - 2, (stripHeight - flagSize.height) / 2, flagSize.width, flagSize.height);
        [canvas addSubview:flagLabel];

        NSTextField *sourceLabel = termLabel(titleStr, 11.5, NSFontWeightRegular, [ink colorWithAlphaComponent:0.7]);
        NSSize sourceSize = sourceLabel.fittingSize;
        CGFloat sourceX = NSMaxX(flagLabel.frame) + 6;
        sourceLabel.frame = NSMakeRect(sourceX, (stripHeight - sourceSize.height) / 2,
                                       MIN(sourceSize.width, NSMinX(closeFrame) - 8 - sourceX), sourceSize.height);
        [canvas addSubview:sourceLabel];

        NSButton *closeButton = [[NSButton alloc] initWithFrame:closeFrame];
        closeButton.bordered = NO;
        [closeButton setButtonType:NSButtonTypeMomentaryPushIn];
        closeButton.title = @"";
        closeButton.image = termCloseGlyph(ink);
        closeButton.imagePosition = NSImageOnly;
        // The glyph is an image, so VoiceOver needs a name for the control.
        closeButton.accessibilityLabel = @"Dismiss blocker";
        closeButton.tag = ++_blockerNextToken;
        NSNumber *tok = [NSNumber numberWithInteger:closeButton.tag];
        closeButton.target = _blockerController;
        closeButton.action = @selector(dismiss:);
        [canvas addSubview:closeButton];
        [closeButton release];

        // A blocker is read at once, so its body appears whole (no typing).
        NSTextView *bodyView = makeTermBodyView(NSMakeRect(kTermInset, bodyTop, kTermWidth - 2 * kTermInset, bodyHeight),
                                                termBody(shownBody, termColor(0xF6ECEC, 1.0)));
        [canvas addSubview:bodyView];

        panel.contentView = surface;
        [surface release];

        // New blocker takes the top slot; reflow slides the older ones down.
        [_blockerOrder insertObject:tok atIndex:0];
        [_blockerPanels setObject:panel forKey:tok];

        // Fade in
        panel.alphaValue = 0;
        [panel orderFront:nil];
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *ctx) {
            ctx.duration = 0.3;
            panel.animator.alphaValue = 1.0;
        }];

        // Persistent: no auto-dismiss timer, unlike the overlay.

        reflowBlockers();
    });
}
