#import <AppKit/AppKit.h>
#include <math.h>
#include <stdint.h>
#import "displays.h"

#ifndef HOOD_BUILD_VERSION
#define HOOD_BUILD_VERSION "unknown"
#endif
#ifndef HOOD_BUILD_TYPE
#define HOOD_BUILD_TYPE "unknown"
#endif

typedef struct {
    char display[37];
    int32_t edge, icon_size, corner_radius;
    uint32_t background_rgb;
    int32_t icon_gap, horizontal_margin, vertical_margin;
    int32_t screen_edge_gap, show_hide_delay_ms;
    int32_t auto_hide, animation_tenths, tooltip_delay_ms;
    int32_t hover_wave, magnification_percent;
    int32_t hover_animation_tenths;
    int32_t tooltip_opacity_percent;
    int32_t separate_windows;
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
    HoodDisplay,
    HoodSeparateWindows,
};

// The selected color is data, not the button's appearance. AppKit supplies the
// same theme-aware bezel and text treatment as the other Settings controls.
@interface HoodHexColorButton : NSButton
@property (nonatomic, strong) NSColor *color;
@end
@implementation HoodHexColorButton
- (void)setColor:(NSColor *)color {
    _color=color;
    NSColor *rgb=[color colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    self.title=[NSString stringWithFormat:@"#%02X%02X%02X",
        (unsigned)lround(rgb.redComponent*255),
        (unsigned)lround(rgb.greenComponent*255),
        (unsigned)lround(rgb.blueComponent*255)];
    self.accessibilityValue=self.title;
}
@end

@interface HoodFastTooltipButton : NSButton
@property (nonatomic, copy) NSString *fastToolTip;
@property NSTrackingArea *hoverTrackingArea;
@property NSPanel *fastToolTipWindow;
@end

@implementation HoodFastTooltipButton
- (void)setFastToolTip:(NSString *)fastToolTip {
    _fastToolTip = [fastToolTip copy];
    if (!_fastToolTip) {
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(showFastToolTip) object:nil];
        [self.fastToolTipWindow orderOut:nil];
    }
}
- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (self.hoverTrackingArea) [self removeTrackingArea:self.hoverTrackingArea];
    self.hoverTrackingArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect
        options:NSTrackingMouseEnteredAndExited|NSTrackingActiveAlways|NSTrackingInVisibleRect
        owner:self userInfo:nil];
    [self addTrackingArea:self.hoverTrackingArea];
}
- (void)mouseEntered:(NSEvent *)event {
    (void)event;
    if (self.fastToolTip) [self performSelector:@selector(showFastToolTip) withObject:nil afterDelay:0.2];
}
- (void)mouseExited:(NSEvent *)event {
    (void)event;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(showFastToolTip) object:nil];
    [self.fastToolTipWindow orderOut:nil];
}
- (void)showFastToolTip {
    if (!self.fastToolTip || !self.window) return;
    NSFont *font = [NSFont menuFontOfSize:12];
    NSDictionary *attributes = @{NSFontAttributeName:font};
    CGFloat width = ceil([self.fastToolTip sizeWithAttributes:attributes].width) + 18;
    CGFloat height = 24;
    if (!self.fastToolTipWindow) {
        self.fastToolTipWindow = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, width, height)
            styleMask:NSWindowStyleMaskBorderless|NSWindowStyleMaskNonactivatingPanel
            backing:NSBackingStoreBuffered defer:NO];
        self.fastToolTipWindow.opaque = NO;
        self.fastToolTipWindow.backgroundColor = NSColor.clearColor;
        self.fastToolTipWindow.ignoresMouseEvents = YES;
        self.fastToolTipWindow.hasShadow = YES;
        self.fastToolTipWindow.level = NSPopUpMenuWindowLevel;
        self.fastToolTipWindow.contentView.wantsLayer = YES;
        self.fastToolTipWindow.contentView.layer.cornerRadius = 6;
        self.fastToolTipWindow.contentView.layer.backgroundColor = NSColor.controlBackgroundColor.CGColor;
        NSTextField *label = [NSTextField labelWithString:@""];
        label.tag = 1;
        label.alignment = NSTextAlignmentCenter;
        label.font = font;
        label.textColor = NSColor.labelColor;
        [self.fastToolTipWindow.contentView addSubview:label];
    }
    NSTextField *label = (NSTextField *)[self.fastToolTipWindow.contentView viewWithTag:1];
    label.stringValue = self.fastToolTip;
    label.frame = NSMakeRect(9, 4, width - 18, 16);
    NSRect frame = self.fastToolTipWindow.frame;
    frame.size = NSMakeSize(width, height);
    NSRect button = [self.window convertRectToScreen:[self convertRect:self.bounds toView:nil]];
    NSRect available = self.window.screen.visibleFrame;
    frame.origin.x = NSMidX(button) - width / 2;
    frame.origin.y = NSMinY(button) - height - 5;
    frame.origin.x = MAX(NSMinX(available), MIN(frame.origin.x, NSMaxX(available) - width));
    frame.origin.y = MAX(NSMinY(available), MIN(frame.origin.y, NSMaxY(available) - height));
    [self.fastToolTipWindow setFrame:frame display:YES];
    [self.fastToolTipWindow orderFrontRegardless];
}
@end

@interface HoodSettingsController : NSObject <NSWindowDelegate, NSApplicationDelegate>
@property HoodSettingsState state;
@property HoodSettingsEvents events;
@property NSWindow *window;
@property NSArray *displayChoices;
@property NSMutableDictionary<NSNumber *, NSControl *> *controls;
@property NSMutableDictionary<NSNumber *, NSTextField *> *valueLabels;
@property NSView *showAnimationRow;
@property NSView *showDelayRow;
@property NSTextField *saveError;
@property NSTextField *memoryLabel;
@property NSTextField *cpuLabel;
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
    label.autoresizingMask = NSViewWidthSizable;
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
    NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 85, 28)];
    NSTextField *value = hood_label(@"");
    value.alignment = NSTextAlignmentRight;
    value.frame = NSMakeRect(0, 5, 60, 20);
    value.autoresizingMask = NSViewMinXMargin;
    NSStepper *stepper = [[NSStepper alloc] initWithFrame:NSMakeRect(66, 3, 19, 24)];
    stepper.autoresizingMask = NSViewMinXMargin;
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

- (void)refreshDisplays {
    NSPopUpButton *popup=(NSPopUpButton *)self.controls[@(HoodDisplay)];
    if(!popup) return;
    NSMutableArray *choices=[NSMutableArray arrayWithObjects:@[@"Primary display",@""], @[@"All displays",@"all"], nil];
    NSString *selected=[NSString stringWithUTF8String:self.state.display];
    BOOL found=selected.length==0 || [selected isEqualToString:@"all"];
    NSUInteger index=0;
    for(NSScreen *screen in NSScreen.screens) {
        NSString *key=hood_display_key(screen);
        if(!key.length) continue;
        NSString *name=[NSString stringWithFormat:@"%lu: %@",(unsigned long)++index,screen.localizedName];
        [choices addObject:@[name,key]];
        found |= [key caseInsensitiveCompare:selected]==NSOrderedSame;
    }
    if(!found) [choices addObject:@[@"Disconnected (using primary)",selected]];
    if(![choices isEqualToArray:self.displayChoices]) {
        self.displayChoices=choices;
        [popup removeAllItems];
        for(NSArray *choice in choices) {
            [popup addItemWithTitle:choice[0]];
            popup.lastItem.representedObject=choice[1];
        }
    }
    for(NSMenuItem *item in popup.itemArray)
        if([item.representedObject caseInsensitiveCompare:selected]==NSOrderedSame) [popup selectItem:item];
}

- (NSView *)settingsView {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 880, 450)];
    NSStackView *left = [[NSStackView alloc] initWithFrame:NSZeroRect];
    NSStackView *right = [[NSStackView alloc] initWithFrame:NSZeroRect];
    for(NSStackView *column in @[left,right]) {
        column.orientation = NSUserInterfaceLayoutOrientationVertical;
        column.alignment = NSLayoutAttributeLeading;
        column.spacing = 5;
        column.translatesAutoresizingMaskIntoConstraints = NO;
        [view addSubview:column];
        [column.topAnchor constraintEqualToAnchor:view.topAnchor constant:16].active = YES;
    }
    [NSLayoutConstraint activateConstraints:@[
        [left.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:18],
        [right.leadingAnchor constraintEqualToAnchor:left.trailingAnchor constant:24],
        [right.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-18],
        [left.widthAnchor constraintEqualToConstant:370],
    ]];
    NSStackView *stack = left;

    NSPopUpButton *display = [self popupWithTag:HoodDisplay titles:@[] values:@[]];
    [stack addArrangedSubview:hood_row(@"Display", display)];
    [self refreshDisplays];

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

    HoodHexColorButton *color = [HoodHexColorButton buttonWithTitle:@"" target:self action:@selector(openBackgroundColor:)];
    color.accessibilityLabel = @"Background color";
    color.tag = HoodBackground;
    color.target = self;
    color.action = @selector(openBackgroundColor:);
    self.controls[@(HoodBackground)] = color;
    [stack addArrangedSubview:hood_row(@"Background color", color)];

    stack = right;
    [stack addArrangedSubview:hood_header(@"Icons")];
    NSPopUpButton *grouping = [self popupWithTag:HoodSeparateWindows
        titles:@[@"By app", @"One icon per window"] values:@[@0, @1]];
    grouping.toolTip = @"One icon per window requires Accessibility access.";
    [stack addArrangedSubview:hood_row(@"Window grouping", grouping)];
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
    self.saveError.frame = NSMakeRect(18, 20, 600, 20);
    [view addSubview:self.saveError];

    NSButton *done = [NSButton buttonWithTitle:@"OK" target:self action:@selector(closeSettings:)];
    done.keyEquivalent = @"\r";
    done.frame = NSMakeRect(782, 14, 80, 30);
    done.autoresizingMask = NSViewMinXMargin;
    [view addSubview:done];
    return view;
}

- (NSView *)runtimeViewBundled:(BOOL)bundled loginAvailable:(BOOL)loginAvailable {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 880, 450)];
    NSTextField *version = hood_label(@"Version: " HOOD_BUILD_VERSION " (" HOOD_BUILD_TYPE ")");
    version.selectable = YES;
    version.frame = NSMakeRect(18, 414, 370, 20);
    [view addSubview:version];
    self.loginButton = [[HoodFastTooltipButton alloc] initWithFrame:NSZeroRect];
    self.loginButton.buttonType = NSButtonTypeSwitch;
    self.loginButton.title = @"Launch at login";
    self.loginButton.target = self;
    self.loginButton.action = @selector(runtimeAction:);
    self.loginButton.tag = HoodLogin;
    self.loginButton.frame = NSMakeRect(18, 370, 250, 24);
    self.loginButton.enabled = bundled && loginAvailable;
    ((HoodFastTooltipButton *)self.loginButton).fastToolTip = self.loginButton.enabled ? nil : @"Available when running Hood.app.";
    [view addSubview:self.loginButton];

    NSTextField *loginDetail = hood_label(@"Start it automatically at login time.");
    loginDetail.frame = NSMakeRect(18, 346, 370, 20);
    loginDetail.textColor = NSColor.secondaryLabelColor;
    [view addSubview:loginDetail];

    self.loginStatus = hood_label(@"");
    self.loginStatus.frame = NSMakeRect(18, 318, 370, 20);
    self.loginStatus.textColor = NSColor.secondaryLabelColor;
    [view addSubview:self.loginStatus];

    NSTextField *stats = hood_label(@"Usage");
    stats.frame = NSMakeRect(412, 412, 450, 22);
    stats.font = [NSFont boldSystemFontOfSize:15];
    [view addSubview:stats];

    NSTextField *statsDetail = hood_label(@"CPU is a rolling five-second average, updated every second.");
    statsDetail.frame = NSMakeRect(412, 384, 450, 20);
    statsDetail.textColor = NSColor.secondaryLabelColor;
    [view addSubview:statsDetail];

    self.cpuLabel = hood_label(@"CPU: unavailable");
    self.cpuLabel.frame = NSMakeRect(412, 340, 450, 22);
    [view addSubview:self.cpuLabel];

    self.memoryLabel = hood_label(@"RAM: unavailable");
    self.memoryLabel.frame = NSMakeRect(412, 296, 450, 22);
    [view addSubview:self.memoryLabel];

    NSTextField *memoryDetail = hood_label(@"It includes the graphics memory.");
    memoryDetail.frame = NSMakeRect(412, 268, 450, 20);
    memoryDetail.textColor = NSColor.secondaryLabelColor;
    [view addSubview:memoryDetail];

    NSButton *quit = [NSButton buttonWithTitle:@"Quit the dock" target:self action:@selector(runtimeAction:)];
    quit.tag = HoodQuit;
    quit.bordered = NO;
    quit.wantsLayer = YES;
    quit.layer.backgroundColor = NSColor.systemRedColor.CGColor;
    quit.layer.cornerRadius = 6;
    quit.contentTintColor = NSColor.whiteColor;
    quit.font = [NSFont systemFontOfSize:14 weight:NSFontWeightMedium];
    quit.frame = NSMakeRect(18, 15, 110, 28);
    [view addSubview:quit];
    // Keep the content anchored to the top when the tab resizes this view.
    for (NSView *child in view.subviews) {
        child.autoresizingMask = NSViewMinYMargin;
    }
    quit.autoresizingMask = NSViewMaxXMargin | NSViewMaxYMargin;
    NSButton *done = [NSButton buttonWithTitle:@"OK" target:self action:@selector(closeSettings:)];
    done.keyEquivalent = @"\r";
    done.frame = NSMakeRect(782, 14, 80, 30);
    done.autoresizingMask = NSViewMinXMargin;
    [view addSubview:done];
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
    [self refreshDisplays];
    [self selectPopup:HoodEdge value:state.edge];
    [self selectPopup:HoodSeparateWindows value:state.separate_windows];
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
    ((HoodHexColorButton *)self.controls[@(HoodBackground)]).color = [NSColor colorWithSRGBRed:red green:green blue:blue alpha:1];
    self.showAnimationRow.hidden = !state.auto_hide;
    self.showDelayRow.hidden = !state.auto_hide;
}

- (NSInteger)popupValue:(NSPopUpButton *)popup {
    return [popup.selectedItem.representedObject integerValue];
}

- (void)openBackgroundColor:(HoodHexColorButton *)sender {
    NSColorPanel *panel=NSColorPanel.sharedColorPanel;
    panel.restorable=NO;
    panel.showsAlpha=NO;
    panel.color=sender.color;
    panel.continuous=YES;
    panel.target=self;
    panel.action=@selector(backgroundColorChanged:);
    [panel makeKeyAndOrderFront:nil];
}

- (void)backgroundColorChanged:(NSColorPanel *)sender {
    HoodHexColorButton *button=(HoodHexColorButton *)self.controls[@(HoodBackground)];
    button.color=sender.color;
    [self controlChanged:button];
}

- (void)controlChanged:(NSControl *)sender {
    NSInteger value = 0;
    HoodSettingsState state = self.state;
    if(sender.tag==HoodDisplay) {
        NSString *key=((NSPopUpButton *)sender).selectedItem.representedObject;
        memset(state.display,0,sizeof(state.display));
        [key getCString:state.display maxLength:sizeof(state.display) encoding:NSUTF8StringEncoding];
    } else if ([sender isKindOfClass:NSPopUpButton.class]) value = [self popupValue:(NSPopUpButton *)sender];
    else if ([sender isKindOfClass:NSStepper.class]) value = sender.integerValue;
    else if ([sender isKindOfClass:NSButton.class]) value = ((NSButton *)sender).state == NSControlStateValueOn;
    switch (sender.tag) {
        case HoodSeparateWindows: state.separate_windows = (int32_t)value; break;
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
            NSColor *color = [((HoodHexColorButton *)sender).color colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
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

// Settings is a short-lived helper; only an explicit color-button click
// should open the system Colors panel in a new session.
- (BOOL)applicationShouldSaveSecureApplicationState:(NSApplication *)app { (void)app; return NO; }
- (BOOL)applicationShouldRestoreSecureApplicationState:(NSApplication *)app { (void)app; return NO; }

- (void)closeSettings:(id)sender { (void)sender; [self.window close]; }
- (void)windowWillClose:(NSNotification *)notification {
    (void)notification;
    if(NSColorPanel.sharedColorPanelExists) {
        NSColorPanel.sharedColorPanel.target=nil;
        [NSColorPanel.sharedColorPanel orderOut:nil];
    }
    HoodSettingsEvents events = self.events;
    events.closed = 1;
    self.events = events;
}
@end

void *hood_settings_create(const HoodSettingsState *state, int bundled, int loginAvailable, int loginEnabled, int loginPending) {
    NSProcessInfo.processInfo.processName = @"Hood Settings";
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    NSMenu *menuBar=[[NSMenu alloc] initWithTitle:@"Hood Settings"];
    NSMenuItem *appItem=[[NSMenuItem alloc] initWithTitle:@"Hood Settings" action:NULL keyEquivalent:@""];
    NSMenu *appMenu=[[NSMenu alloc] initWithTitle:@"Hood Settings"];
    [appMenu addItemWithTitle:@"About Hood Settings" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
    [appMenu addItem:NSMenuItem.separatorItem];
    [appMenu addItemWithTitle:@"Hide Hood Settings" action:@selector(hide:) keyEquivalent:@"h"];
    [appMenu addItem:NSMenuItem.separatorItem];
    [appMenu addItemWithTitle:@"Quit Hood Settings" action:@selector(terminate:) keyEquivalent:@"q"];
    appItem.submenu=appMenu;
    [menuBar addItem:appItem];
    NSApp.mainMenu=menuBar;
    NSString *iconPath=[NSBundle.mainBundle pathForResource:@"Hood" ofType:@"icns"];
    if(iconPath) NSApp.applicationIconImage=[[NSImage alloc] initWithContentsOfFile:iconPath];
    HoodSettingsController *controller = [HoodSettingsController new];
    NSApp.delegate = controller;
    [NSApp finishLaunching];
    if(NSColorPanel.sharedColorPanelExists) [NSColorPanel.sharedColorPanel orderOut:nil];
    controller.controls = [NSMutableDictionary dictionary];
    controller.valueLabels = [NSMutableDictionary dictionary];
    NSRect frame = NSMakeRect(0, 0, 930, 520);
    NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
        styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable|NSWindowStyleMaskMiniaturizable
        backing:NSBackingStoreBuffered defer:NO];
    window.restorable = NO;
    window.title = @"Hood Settings";
    window.releasedWhenClosed = NO;
    window.delegate = controller;
    controller.window = window;

    NSTabView *tabs = [[NSTabView alloc] initWithFrame:NSMakeRect(15, 15, 900, 490)];
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
    [controller refreshDisplays];
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

void hood_settings_set_runtime(void *handle, uint64_t memoryBytes, double cpuPercent, int available,
        int cpuAvailable, int bundled, int loginAvailable, int loginEnabled, int loginPending, int loginFailed) {
    HoodSettingsController *controller = (__bridge HoodSettingsController *)handle;
    controller.memoryLabel.stringValue = available
        ? [NSString stringWithFormat:@"RAM: %.1f MB", memoryBytes / 1000000.0]
        : @"RAM: unavailable";
    controller.cpuLabel.stringValue = cpuAvailable
        ? [NSString stringWithFormat:@"CPU: %.1f%%", cpuPercent]
        : @"CPU: unavailable";
    controller.loginButton.enabled = bundled && loginAvailable;
    ((HoodFastTooltipButton *)controller.loginButton).fastToolTip = controller.loginButton.enabled ? nil : @"Available when running Hood.app.";
    controller.loginButton.state = loginEnabled || loginPending ? NSControlStateValueOn : NSControlStateValueOff;
    controller.loginStatus.textColor = loginFailed ? NSColor.systemRedColor : NSColor.secondaryLabelColor;
    if (loginFailed) controller.loginStatus.stringValue = @"Could not update login item.";
    else if (loginPending) controller.loginStatus.stringValue = @"Allow Hood in System Settings > Login Items.";
    else controller.loginStatus.stringValue = @"";
}
