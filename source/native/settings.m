#import <AppKit/AppKit.h>
#include <math.h>
#include <stdint.h>

typedef struct {
    int32_t edge, icon_size, corner_radius;
    uint32_t background_rgb;
    int32_t icon_gap, horizontal_margin, vertical_margin;
    int32_t screen_edge_gap, show_hide_delay_ms;
    int32_t auto_hide, animation_tenths, tooltip_delay_ms;
    int32_t hover_wave, magnification_percent;
    int32_t hover_animation_tenths;
    int32_t tooltip_opacity_percent;
} HoodSettingsState;

typedef struct { int32_t changed, closed, toggle_login, quit_dock; } HoodSettingsEvents;

enum {
    HoodEdge = 1,
    HoodIconSize,
    HoodCornerRadius,
    HoodBackground,
    HoodIconGap,
    HoodHorizontalMargin,
    HoodVerticalMargin,
    HoodScreenEdgeGap,
    HoodShowHideDelay,
    HoodAutoHide,
    HoodShowAnimation,
    HoodTooltipDelay,
    HoodTooltipOpacity,
    HoodHoverWave,
    HoodMagnification,
    HoodHoverAnimation,
    HoodLogin,
    HoodQuit,
};

@interface HoodSettingsController : NSObject <NSWindowDelegate>
@property HoodSettingsState state;
@property HoodSettingsEvents events;
@property NSWindow *window;
@property NSMutableDictionary<NSNumber *, NSControl *> *controls;
@property NSMutableDictionary<NSNumber *, NSTextField *> *valueLabels;
@property NSView *showAnimationRow;
@property NSView *showDelayRow;
@property NSTextField *saveError;
@property NSTextField *memoryLabel;
@property NSButton *loginButton;
@property NSTextField *loginStatus;
@end

static NSTextField *hood_label(NSString *text) {
    NSTextField *label = [NSTextField labelWithString:text];
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    return label;
}

static NSView *hood_row(NSString *title, NSView *control) {
    NSView *row = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 500, 30)];
    NSTextField *label = hood_label(title);
    label.frame = NSMakeRect(0, 6, 290, 20);
    label.autoresizingMask = NSViewWidthSizable;
    control.frame = NSMakeRect(310, 1, 190, 28);
    control.autoresizingMask = NSViewMinXMargin;
    [row addSubview:label];
    [row addSubview:control];
    [row.heightAnchor constraintEqualToConstant:30].active = YES;
    return row;
}

static NSView *hood_header(NSString *title) {
    NSTextField *label = hood_label(title);
    label.font = [NSFont boldSystemFontOfSize:15];
    NSView *row = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 500, 28)];
    label.frame = NSMakeRect(0, 4, 500, 21);
    [row addSubview:label];
    [row.heightAnchor constraintEqualToConstant:28].active = YES;
    return row;
}

static NSBox *hood_separator(void) {
    NSBox *box = [[NSBox alloc] initWithFrame:NSMakeRect(0, 0, 500, 9)];
    box.boxType = NSBoxSeparator;
    [box.heightAnchor constraintEqualToConstant:9].active = YES;
    return box;
}

@implementation HoodSettingsController

- (NSPopUpButton *)popupWithTag:(NSInteger)tag titles:(NSArray<NSString *> *)titles values:(NSArray<NSNumber *> *)values {
    NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    popup.tag = tag;
    popup.target = self;
    popup.action = @selector(controlChanged:);
    for (NSUInteger i = 0; i < titles.count; i++) {
        [popup addItemWithTitle:titles[i]];
        popup.lastItem.representedObject = values[i];
    }
    self.controls[@(tag)] = popup;
    return popup;
}

- (NSView *)stepperWithTag:(NSInteger)tag minimum:(double)minimum maximum:(double)maximum increment:(double)increment {
    NSView *container = [[NSView alloc] initWithFrame:NSZeroRect];
    NSTextField *value = hood_label(@"");
    value.alignment = NSTextAlignmentRight;
    value.frame = NSMakeRect(0, 5, 150, 20);
    NSStepper *stepper = [[NSStepper alloc] initWithFrame:NSMakeRect(156, 3, 19, 24)];
    stepper.minValue = minimum;
    stepper.maxValue = maximum;
    stepper.increment = increment;
    stepper.valueWraps = NO;
    stepper.tag = tag;
    stepper.target = self;
    stepper.action = @selector(controlChanged:);
    [container addSubview:value];
    [container addSubview:stepper];
    self.controls[@(tag)] = stepper;
    self.valueLabels[@(tag)] = value;
    return container;
}

- (NSButton *)checkboxWithTag:(NSInteger)tag {
    NSButton *checkbox = [NSButton checkboxWithTitle:@"" target:self action:@selector(controlChanged:)];
    checkbox.tag = tag;
    checkbox.alignment = NSTextAlignmentLeft;
    self.controls[@(tag)] = checkbox;
    return checkbox;
}

- (NSView *)settingsView {
    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSMakeRect(0, 0, 500, 680)];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 5;
    stack.edgeInsets = NSEdgeInsetsMake(16, 18, 16, 18);

    NSPopUpButton *show = [self popupWithTag:HoodAutoHide
        titles:@[@"Always", @"Auto-Hide"] values:@[@0, @1]];
    [stack addArrangedSubview:hood_row(@"Show", show)];

    NSPopUpButton *showAnimation = [self popupWithTag:HoodShowAnimation
        titles:@[@"No animation", @"100 ms", @"200 ms", @"300 ms", @"400 ms", @"500 ms"]
        values:@[@0, @1, @2, @3, @4, @5]];
    self.showAnimationRow = hood_row(@"Show/hide animation", showAnimation);
    [stack addArrangedSubview:self.showAnimationRow];

    NSPopUpButton *showDelay = [self popupWithTag:HoodShowHideDelay
        titles:@[@"Immediate", @"50 ms", @"100 ms", @"200 ms", @"300 ms"]
        values:@[@0, @50, @100, @200, @300]];
    self.showDelayRow = hood_row(@"Show/hide delay", showDelay);
    [stack addArrangedSubview:self.showDelayRow];

    NSPopUpButton *position = [self popupWithTag:HoodEdge
        titles:@[@"Left", @"Right", @"Bottom", @"Top"] values:@[@0, @1, @2, @3]];
    [stack addArrangedSubview:hood_row(@"Position", position)];

    NSPopUpButton *tooltip = [self popupWithTag:HoodTooltipDelay
        titles:@[@"Immediate", @"100 ms", @"250 ms", @"450 ms", @"750 ms", @"1 second"]
        values:@[@0, @100, @250, @450, @750, @1000]];
    [stack addArrangedSubview:hood_row(@"Tooltip delay", tooltip)];
    [stack addArrangedSubview:hood_row(@"Tooltip opacity", [self stepperWithTag:HoodTooltipOpacity minimum:20 maximum:100 increment:5])];
    [stack addArrangedSubview:hood_row(@"Corner radius", [self stepperWithTag:HoodCornerRadius minimum:0 maximum:24 increment:2])];

    NSColorWell *color = [[NSColorWell alloc] initWithFrame:NSZeroRect];
    color.tag = HoodBackground;
    color.target = self;
    color.action = @selector(controlChanged:);
    self.controls[@(HoodBackground)] = color;
    [stack addArrangedSubview:hood_row(@"Background color", color)];

    [stack addArrangedSubview:hood_separator()];
    [stack addArrangedSubview:hood_header(@"Icons")];
    [stack addArrangedSubview:hood_row(@"Size", [self stepperWithTag:HoodIconSize minimum:24 maximum:48 increment:4])];
    [stack addArrangedSubview:hood_row(@"Magnification with wave effect", [self checkboxWithTag:HoodHoverWave])];

    NSPopUpButton *magnification = [self popupWithTag:HoodMagnification
        titles:@[@"Off", @"5%", @"10%", @"15%", @"20%", @"25%", @"30%", @"40%", @"50%", @"60%"]
        values:@[@0, @5, @10, @15, @20, @25, @30, @40, @50, @60]];
    [stack addArrangedSubview:hood_row(@"Magnification size", magnification)];

    NSPopUpButton *hoverAnimation = [self popupWithTag:HoodHoverAnimation
        titles:@[@"100 ms", @"200 ms", @"300 ms", @"400 ms", @"500 ms"]
        values:@[@1, @2, @3, @4, @5]];
    [stack addArrangedSubview:hood_row(@"Magnification animation", hoverAnimation)];

    [stack addArrangedSubview:hood_separator()];
    [stack addArrangedSubview:hood_header(@"Spacing")];
    [stack addArrangedSubview:hood_row(@"Between icons", [self stepperWithTag:HoodIconGap minimum:0 maximum:48 increment:2])];
    [stack addArrangedSubview:hood_row(@"Left / right margins", [self stepperWithTag:HoodHorizontalMargin minimum:0 maximum:48 increment:2])];
    [stack addArrangedSubview:hood_row(@"Top / bottom margins", [self stepperWithTag:HoodVerticalMargin minimum:0 maximum:48 increment:2])];
    [stack addArrangedSubview:hood_row(@"Between Dock and screen edge", [self stepperWithTag:HoodScreenEdgeGap minimum:0 maximum:20 increment:1])];

    self.saveError = hood_label(@"Could not save hood.toml");
    self.saveError.textColor = NSColor.systemRedColor;
    self.saveError.hidden = YES;
    [self.saveError.heightAnchor constraintEqualToConstant:20].active = YES;
    [stack addArrangedSubview:self.saveError];

    NSButton *done = [NSButton buttonWithTitle:@"OK" target:self action:@selector(closeSettings:)];
    done.keyEquivalent = @"\r";
    NSView *doneRow = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 500, 34)];
    done.frame = NSMakeRect(420, 2, 80, 30);
    done.autoresizingMask = NSViewMinXMargin;
    [doneRow addSubview:done];
    [doneRow.heightAnchor constraintEqualToConstant:34].active = YES;
    [stack addArrangedSubview:doneRow];
    return stack;
}

- (NSView *)runtimeViewBundled:(BOOL)bundled loginAvailable:(BOOL)loginAvailable {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 500, 620)];
    self.memoryLabel = hood_label(@"Memory usage: unavailable");
    self.memoryLabel.frame = NSMakeRect(20, 560, 460, 22);
    self.memoryLabel.font = [NSFont systemFontOfSize:14 weight:NSFontWeightMedium];
    [view addSubview:self.memoryLabel];

    NSTextField *detail = hood_label(@"Includes graphics memory. Updates every second.");
    detail.frame = NSMakeRect(20, 532, 460, 20);
    detail.textColor = NSColor.secondaryLabelColor;
    [view addSubview:detail];

    self.loginButton = [NSButton checkboxWithTitle:@"Launch at login" target:self action:@selector(runtimeAction:)];
    self.loginButton.tag = HoodLogin;
    self.loginButton.frame = NSMakeRect(20, 476, 250, 24);
    self.loginButton.enabled = bundled && loginAvailable;
    [view addSubview:self.loginButton];

    self.loginStatus = hood_label(@"");
    self.loginStatus.frame = NSMakeRect(20, 446, 460, 20);
    self.loginStatus.textColor = NSColor.secondaryLabelColor;
    [view addSubview:self.loginStatus];

    NSButton *quit = [NSButton buttonWithTitle:@"Quit Hood" target:self action:@selector(runtimeAction:)];
    quit.tag = HoodQuit;
    quit.bezelStyle = NSBezelStyleRounded;
    quit.frame = NSMakeRect(20, 382, 100, 32);
    [view addSubview:quit];
    return view;
}

- (void)selectPopup:(NSInteger)tag value:(NSInteger)value {
    NSPopUpButton *popup = (NSPopUpButton *)self.controls[@(tag)];
    for (NSMenuItem *item in popup.itemArray) {
        if ([item.representedObject integerValue] == value) {
            [popup selectItem:item];
            return;
        }
    }
}

- (void)setStepper:(NSInteger)tag value:(NSInteger)value {
    NSStepper *stepper = (NSStepper *)self.controls[@(tag)];
    stepper.integerValue = value;
    NSString *suffix = tag == HoodTooltipOpacity ? @"%" : @" px";
    self.valueLabels[@(tag)].stringValue = [NSString stringWithFormat:@"%ld%@", (long)value, suffix];
}

- (void)applyState:(HoodSettingsState)state {
    self.state = state;
    [self selectPopup:HoodEdge value:state.edge];
    [self setStepper:HoodIconSize value:state.icon_size];
    [self setStepper:HoodCornerRadius value:state.corner_radius];
    [self setStepper:HoodIconGap value:state.icon_gap];
    [self setStepper:HoodHorizontalMargin value:state.horizontal_margin];
    [self setStepper:HoodVerticalMargin value:state.vertical_margin];
    [self setStepper:HoodScreenEdgeGap value:state.screen_edge_gap];
    [self selectPopup:HoodShowHideDelay value:state.show_hide_delay_ms];
    [self selectPopup:HoodAutoHide value:state.auto_hide];
    [self selectPopup:HoodShowAnimation value:state.animation_tenths];
    [self selectPopup:HoodTooltipDelay value:state.tooltip_delay_ms];
    [self setStepper:HoodTooltipOpacity value:state.tooltip_opacity_percent];
    ((NSButton *)self.controls[@(HoodHoverWave)]).state = state.hover_wave ? NSControlStateValueOn : NSControlStateValueOff;
    [self selectPopup:HoodMagnification value:state.magnification_percent];
    [self selectPopup:HoodHoverAnimation value:state.hover_animation_tenths];
    CGFloat red = ((state.background_rgb >> 16) & 255) / 255.0;
    CGFloat green = ((state.background_rgb >> 8) & 255) / 255.0;
    CGFloat blue = (state.background_rgb & 255) / 255.0;
    ((NSColorWell *)self.controls[@(HoodBackground)]).color = [NSColor colorWithSRGBRed:red green:green blue:blue alpha:1];
    self.showAnimationRow.hidden = !state.auto_hide;
    self.showDelayRow.hidden = !state.auto_hide;
}

- (NSInteger)popupValue:(NSPopUpButton *)popup {
    return [popup.selectedItem.representedObject integerValue];
}

- (void)controlChanged:(NSControl *)sender {
    NSInteger value = 0;
    HoodSettingsState state = self.state;
    if ([sender isKindOfClass:NSPopUpButton.class]) value = [self popupValue:(NSPopUpButton *)sender];
    else if ([sender isKindOfClass:NSStepper.class]) value = sender.integerValue;
    else if ([sender isKindOfClass:NSButton.class]) value = ((NSButton *)sender).state == NSControlStateValueOn;
    switch (sender.tag) {
        case HoodEdge: state.edge = (int32_t)value; break;
        case HoodIconSize: state.icon_size = (int32_t)value; break;
        case HoodCornerRadius: state.corner_radius = (int32_t)value; break;
        case HoodIconGap: state.icon_gap = (int32_t)value; break;
        case HoodHorizontalMargin: state.horizontal_margin = (int32_t)value; break;
        case HoodVerticalMargin: state.vertical_margin = (int32_t)value; break;
        case HoodScreenEdgeGap: state.screen_edge_gap = (int32_t)value; break;
        case HoodShowHideDelay: state.show_hide_delay_ms = (int32_t)value; break;
        case HoodAutoHide:
            state.auto_hide = (int32_t)value;
            self.showAnimationRow.hidden = !value;
            self.showDelayRow.hidden = !value;
            break;
        case HoodShowAnimation: state.animation_tenths = (int32_t)value; break;
        case HoodTooltipDelay: state.tooltip_delay_ms = (int32_t)value; break;
        case HoodTooltipOpacity: state.tooltip_opacity_percent = (int32_t)value; break;
        case HoodHoverWave: state.hover_wave = (int32_t)value; break;
        case HoodMagnification: state.magnification_percent = (int32_t)value; break;
        case HoodHoverAnimation: state.hover_animation_tenths = (int32_t)value; break;
        case HoodBackground: {
            NSColor *color = [((NSColorWell *)sender).color colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
            state.background_rgb = ((uint32_t)lround(color.redComponent * 255) << 16) |
                ((uint32_t)lround(color.greenComponent * 255) << 8) |
                (uint32_t)lround(color.blueComponent * 255);
            break;
        }
    }
    if ([sender isKindOfClass:NSStepper.class]) [self setStepper:sender.tag value:value];
    self.state = state;
    HoodSettingsEvents events = self.events;
    events.changed = 1;
    self.events = events;
}

- (void)runtimeAction:(NSButton *)sender {
    HoodSettingsEvents events = self.events;
    if (sender.tag == HoodLogin) events.toggle_login = 1;
    if (sender.tag == HoodQuit) events.quit_dock = 1;
    self.events = events;
}

- (void)closeSettings:(id)sender { (void)sender; [self.window close]; }
- (void)windowWillClose:(NSNotification *)notification {
    (void)notification;
    HoodSettingsEvents events = self.events;
    events.closed = 1;
    self.events = events;
}
@end

void *hood_settings_create(const HoodSettingsState *state, int bundled, int loginAvailable, int loginEnabled, int loginPending) {
    NSProcessInfo.processInfo.processName = @"Hood Settings";
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    [NSApp finishLaunching];

    HoodSettingsController *controller = [HoodSettingsController new];
    controller.controls = [NSMutableDictionary dictionary];
    controller.valueLabels = [NSMutableDictionary dictionary];
    NSRect frame = NSMakeRect(0, 0, 550, 720);
    NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
        styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable
        backing:NSBackingStoreBuffered defer:NO];
    window.title = @"Hood Settings";
    window.releasedWhenClosed = NO;
    window.delegate = controller;
    controller.window = window;

    NSTabView *tabs = [[NSTabView alloc] initWithFrame:NSMakeRect(15, 15, 520, 690)];
    tabs.autoresizingMask = NSViewWidthSizable|NSViewHeightSizable;
    NSTabViewItem *settingsTab = [[NSTabViewItem alloc] initWithIdentifier:@"settings"];
    settingsTab.label = @"Settings";
    settingsTab.view = [controller settingsView];
    [tabs addTabViewItem:settingsTab];
    NSTabViewItem *runtimeTab = [[NSTabViewItem alloc] initWithIdentifier:@"runtime"];
    runtimeTab.label = @"Runtime";
    runtimeTab.view = [controller runtimeViewBundled:bundled loginAvailable:loginAvailable];
    [tabs addTabViewItem:runtimeTab];
    window.contentView = [[NSView alloc] initWithFrame:frame];
    [window.contentView addSubview:tabs];
    [controller applyState:*state];
    controller.loginButton.state = loginEnabled || loginPending ? NSControlStateValueOn : NSControlStateValueOff;
    [window center];
    [window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    return (__bridge_retained void *)controller;
}

void hood_settings_close(void *handle) {
    HoodSettingsController *controller = CFBridgingRelease(handle);
    [controller.window close];
}

void hood_settings_poll(void *handle, HoodSettingsState *state, HoodSettingsEvents *events, double wait) {
    HoodSettingsController *controller = (__bridge HoodSettingsController *)handle;
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:wait];
    for (;;) {
        NSEvent *event = [NSApp nextEventMatchingMask:NSEventMaskAny untilDate:deadline
            inMode:NSDefaultRunLoopMode dequeue:YES];
        if (!event) break;
        deadline = NSDate.distantPast;
        [NSApp sendEvent:event];
    }
    [NSApp updateWindows];
    *state = controller.state;
    *events = controller.events;
    controller.events = (HoodSettingsEvents){0};
}

void hood_settings_update(void *handle, const HoodSettingsState *state) {
    HoodSettingsController *controller = (__bridge HoodSettingsController *)handle;
    [controller applyState:*state];
}

void hood_settings_set_save_failed(void *handle, int failed) {
    HoodSettingsController *controller = (__bridge HoodSettingsController *)handle;
    controller.saveError.hidden = !failed;
}

void hood_settings_set_runtime(void *handle, uint64_t memoryBytes, int available, int bundled,
        int loginAvailable, int loginEnabled, int loginPending, int loginFailed) {
    HoodSettingsController *controller = (__bridge HoodSettingsController *)handle;
    controller.memoryLabel.stringValue = available
        ? [NSString stringWithFormat:@"Memory usage: %.1f MB", memoryBytes / 1000000.0]
        : @"Memory usage: unavailable";
    controller.loginButton.enabled = bundled && loginAvailable;
    controller.loginButton.state = loginEnabled || loginPending ? NSControlStateValueOn : NSControlStateValueOff;
    controller.loginStatus.textColor = loginFailed ? NSColor.systemRedColor : NSColor.secondaryLabelColor;
    if (!bundled) controller.loginStatus.stringValue = @"Available when running Hood.app.";
    else if (loginFailed) controller.loginStatus.stringValue = @"Could not update login item.";
    else if (loginPending) controller.loginStatus.stringValue = @"Allow Hood in System Settings > Login Items.";
    else if (!loginAvailable) controller.loginStatus.stringValue = @"Launch at login is unavailable on this Mac.";
    else controller.loginStatus.stringValue = @"Automatically starts Hood when you log in.";
}
