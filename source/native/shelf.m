#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import <ApplicationServices/ApplicationServices.h>
#include <stdint.h>
#include <time.h>
#include <math.h>
#import "displays.h"

typedef struct { int32_t pressed, released, down, right, escape; double wheel; } HoodInput;
@interface HoodView : NSView
@end
@implementation HoodView
- (BOOL)acceptsFirstMouse:(NSEvent *)event { (void)event; return YES; }
@end
@interface HoodPanel : NSPanel
@property NSMutableArray<CALayer *> *items;
@property CALayer *background;
@property NSUInteger cursor;
@property HoodInput pendingInput;
@end
@implementation HoodPanel
- (BOOL)canBecomeKeyWindow { return YES; }
@end

double hood_time(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC,&t); return t.tv_sec+t.tv_nsec/1e9; }
static void hood_initialize(void) {
    static BOOL initialized=NO;
    if(initialized) return;
    initialized=YES;
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    [NSApp finishLaunching];
}
void *hood_create(void) {
    hood_initialize();
    HoodPanel *w=[[HoodPanel alloc] initWithContentRect:NSMakeRect(0,0,80,80)
        styleMask:NSWindowStyleMaskBorderless|NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:NO];
    w.releasedWhenClosed=NO; w.opaque=NO; w.backgroundColor=NSColor.clearColor;
    w.level=NSFloatingWindowLevel; w.hidesOnDeactivate=NO; w.hasShadow=NO;
    w.collectionBehavior=NSWindowCollectionBehaviorMoveToActiveSpace;
    w.contentView=[[HoodView alloc] initWithFrame:NSMakeRect(0,0,80,80)];
    w.contentView.wantsLayer=YES;
    w.contentView.layer.masksToBounds=YES;
    w.items=[NSMutableArray array];
    w.background=[CALayer layer];
    [w.contentView.layer addSublayer:w.background];
    [w orderFrontRegardless];
    return (__bridge_retained void *)w;
}
void hood_close(void *handle) { HoodPanel *w=CFBridgingRelease(handle); [w close]; }
void hood_poll(void *handle, HoodInput *input, double wait) {
    hood_initialize();
    HoodPanel *w=(__bridge HoodPanel *)handle;
    *input=(HoodInput){0};
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:wait];
    for (;;) {
        NSEvent *e=[NSApp nextEventMatchingMask:NSEventMaskAny untilDate:deadline inMode:NSDefaultRunLoopMode dequeue:YES];
        if(!e) break;
        deadline=NSDate.distantPast;
        if([e.window isKindOfClass:HoodPanel.class]) {
            HoodPanel *target=(HoodPanel *)e.window;
            HoodInput pending=target.pendingInput;
            switch(e.type) {
                case NSEventTypeLeftMouseDown: pending.pressed=1; break;
                case NSEventTypeLeftMouseUp: pending.released=1; break;
                case NSEventTypeRightMouseUp: pending.right=1; break;
                case NSEventTypeScrollWheel: pending.wheel+=e.scrollingDeltaY/(e.hasPreciseScrollingDeltas?10:1); break;
                case NSEventTypeKeyDown: if(e.keyCode==53) pending.escape=1; break;
                default: break;
            }
            target.pendingInput=pending;
        }
        [NSApp sendEvent:e];
    }
    if(w) {
        *input=w.pendingInput;
        w.pendingInput=(HoodInput){0};
    }
    input->down=([NSEvent pressedMouseButtons]&1)!=0;
    [NSApp updateWindows];
}
void hood_begin(void *handle, uint32_t rgb, double radius,float x,float y,float width,float height) {
    HoodPanel *w=(__bridge HoodPanel *)handle;
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    w.cursor=0;
    w.contentView.layer.backgroundColor=NSColor.clearColor.CGColor;
    w.background.frame=CGRectMake(x,w.contentView.bounds.size.height-y-height,width,height);
    w.background.cornerRadius=radius;
    // A restrained outline follows the dock, not the transparent hover canvas.
    w.background.borderWidth=1;
    w.background.borderColor=[NSColor colorWithWhite:1 alpha:0.16].CGColor;
    w.background.backgroundColor=[NSColor colorWithSRGBRed:((rgb>>16)&255)/255.0 green:((rgb>>8)&255)/255.0 blue:(rgb&255)/255.0 alpha:1].CGColor;
}
void hood_icon(void *handle, void *image,float x,float y,float width,float height) {
    HoodPanel *w=(__bridge HoodPanel *)handle;
    if(w.cursor==w.items.count) { CALayer *layer=[CALayer layer]; [w.items addObject:layer]; [w.contentView.layer addSublayer:layer]; }
    CALayer *layer=w.items[w.cursor++];
    layer.hidden=NO; layer.frame=CGRectMake(x,w.contentView.bounds.size.height-y-height,width,height);
    layer.contents=(__bridge id)image;
    layer.contentsGravity=kCAGravityResizeAspect;
    layer.contentsScale=w.backingScaleFactor;
    layer.backgroundColor=image?nil:NSColor.grayColor.CGColor;
    layer.cornerRadius=image?0:width/2;
}
void hood_end(void *handle) {
    HoodPanel *w=(__bridge HoodPanel *)handle;
    while(w.items.count>w.cursor) { [w.items.lastObject removeFromSuperlayer]; [w.items removeLastObject]; }
    [CATransaction commit]; [CATransaction flush];
}
// Popup controls must handle the first click while another app is active.
@interface HoodPopupButton : NSButton
@end
@implementation HoodPopupButton
- (BOOL)acceptsFirstMouse:(NSEvent *)event { (void)event; return YES; }
- (BOOL)needsPanelToBecomeKey { return NO; }
@end

static CGFloat hood_linear(CGFloat c) {
    return c<=0.04045?c/12.92:pow((c+0.055)/1.055,2.4);
}
static CGFloat hood_luminance(NSColor *color) {
    NSColor *rgb=[color colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    return 0.2126*hood_linear(rgb.redComponent)+0.7152*hood_linear(rgb.greenComponent)+0.0722*hood_linear(rgb.blueComponent);
}
static NSColor *hood_text_color(NSColor *background) {
    return hood_luminance(background)>0.179?NSColor.blackColor:NSColor.whiteColor;
}
@interface HoodWindowButton : HoodPopupButton
@property NSColor *popupColor;
@property NSTrackingArea *hoverArea;
@property BOOL hovered;
@end
@implementation HoodWindowButton
- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if(self.hoverArea) [self removeTrackingArea:self.hoverArea];
    self.hoverArea=[[NSTrackingArea alloc] initWithRect:NSZeroRect
        options:NSTrackingMouseEnteredAndExited|NSTrackingActiveAlways|NSTrackingInVisibleRect
        owner:self userInfo:nil];
    [self addTrackingArea:self.hoverArea];
    NSPoint pointer=[self convertPoint:self.window.mouseLocationOutsideOfEventStream fromView:nil];
    self.hovered=self.window && NSPointInRect(pointer,self.visibleRect);
    self.needsDisplay=YES;
}
- (void)mouseEntered:(NSEvent *)event { (void)event; self.hovered=YES; self.needsDisplay=YES; }
- (void)mouseExited:(NSEvent *)event { (void)event; self.hovered=NO; self.needsDisplay=YES; }
- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    NSColor *background=self.popupColor ?: NSColor.darkGrayColor;
    CGFloat luminance=hood_luminance(background);
    CGFloat low=hood_linear(37/255.0), high=hood_linear(80/255.0);
    // Choose a direction without reducing the shading amount to zero in
    // the middle of the #252525–#505050 range.
    BOOL lighten=luminance<(low+high)/2;
    CGFloat amount=(self.hovered || self.cell.highlighted)?0.20:0.08;
    if(!lighten) {
        // Black has less room to shade a dark background. Scale the blend
        // by its brightest sRGB channel, keeping the adjustment bounded.
        NSColor *rgb=[background colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
        CGFloat brightness=MAX(rgb.redComponent,MAX(rgb.greenComponent,rgb.blueComponent));
        CGFloat limit=(self.hovered || self.cell.highlighted)?0.35:0.20;
        amount=MIN(limit,amount/MAX(brightness,0.01));
    }
    NSColor *accent=lighten?NSColor.whiteColor:NSColor.blackColor;
    NSColor *fill=[background blendedColorWithFraction:amount ofColor:accent];
    [fill setFill];
    [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds,0,3) xRadius:6 yRadius:6] fill];
    NSColor *text=hood_text_color(fill);
    NSMutableParagraphStyle *style=[[NSMutableParagraphStyle alloc] init];
    style.alignment=NSTextAlignmentCenter;
    style.lineBreakMode=NSLineBreakByTruncatingTail;
    NSFont *font=self.font ?: [NSFont systemFontOfSize:13];
    NSDictionary *attributes=@{NSFontAttributeName:font,NSForegroundColorAttributeName:text,NSParagraphStyleAttributeName:style};
    CGFloat height=ceil(font.ascender-font.descender);
    [self.title drawInRect:NSMakeRect(10,(self.bounds.size.height-height)/2,self.bounds.size.width-20,height) withAttributes:attributes];
}
@end

// Retain AX elements in the popup so each action addresses the selected window.
@interface HoodTooltip : NSPanel
@property pid_t pid;
@property double nextRefresh;
@property double lastInside;
@property NSArray *windows;
@property BOOL needsAccess;
@property NSScrollView *list;
- (void)windowAction:(NSButton *)sender;
- (void)enableAccess:(id)sender;
@end
static id hood_ax_value(AXUIElementRef element, CFStringRef attribute) {
    CFTypeRef value=NULL;
    if(AXUIElementCopyAttributeValue(element,attribute,&value)!=kAXErrorSuccess) return nil;
    return CFBridgingRelease(value);
}
static BOOL hood_ax_standard_window(AXUIElementRef element) {
    NSString *role=hood_ax_value(element,kAXRoleAttribute);
    NSString *subrole=hood_ax_value(element,kAXSubroleAttribute);
    return [role isEqualToString:(__bridge NSString *)kAXWindowRole] &&
        [subrole isEqualToString:(__bridge NSString *)kAXStandardWindowSubrole];
}
@implementation HoodTooltip
- (BOOL)canBecomeKeyWindow { return YES; }
- (void)enableAccess:(id)sender {
    (void)sender;
    AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)@{(__bridge NSString *)kAXTrustedCheckOptionPrompt:@YES});
    NSURL *settingsURL=[NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"];
    NSURL *appURL=[NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:@"com.apple.systempreferences"];
    void (^showHelp)(void)=^{
        NSAlert *alert=[[NSAlert alloc] init];
        alert.messageText=@"Allow Hood to control windows";
        alert.informativeText=@"Open System Settings → Privacy & Security → Accessibility, then enable Hood (or the hood development executable). If it is missing, use + to add it.";
        [alert runModal];
    };
    if(appURL) {
        NSWorkspaceOpenConfiguration *configuration=[NSWorkspaceOpenConfiguration configuration];
        configuration.activates=YES;
        [NSWorkspace.sharedWorkspace openURLs:@[settingsURL] withApplicationAtURL:appURL
            configuration:configuration completionHandler:^(NSRunningApplication *app, NSError *error) {
                (void)app;
                if(error) dispatch_async(dispatch_get_main_queue(),showHelp);
            }];
    } else {
        showHelp();
    }
    self.nextRefresh=0;
}
- (void)windowAction:(NSButton *)sender {
    NSUInteger index=sender.tag;
    if(index>=self.windows.count) return;
    AXUIElementRef window=(__bridge AXUIElementRef)self.windows[index];
    NSRunningApplication *app=[NSRunningApplication runningApplicationWithProcessIdentifier:self.pid];
    // Read live state at click time: another app or window may have gained focus
    // since this list was populated. The nonactivating popup preserves focus.
    id minimizedValue=hood_ax_value(window,kAXMinimizedAttribute);
    if(!minimizedValue || !app || app.terminated) { NSBeep(); self.nextRefresh=0; return; }
    BOOL minimized=[minimizedValue boolValue];
    AXUIElementRef application=AXUIElementCreateApplication(self.pid);
    id focused=hood_ax_value(application,kAXFocusedWindowAttribute);
    CFRelease(application);
    BOOL active=app.active && !app.hidden && focused && CFEqual((__bridge CFTypeRef)focused,window);
    BOOL minimize=!minimized && active;
    if(minimized || minimize) {
        AXError error=AXUIElementSetAttributeValue(window,kAXMinimizedAttribute,minimize?kCFBooleanTrue:kCFBooleanFalse);
        if(error!=kAXErrorSuccess) { NSBeep(); self.nextRefresh=0; return; }
    }
    if(!minimize) {
        [app unhide];
        [app activateWithOptions:0];
        AXUIElementSetAttributeValue(window,kAXMainAttribute,kCFBooleanTrue);
        if(AXUIElementPerformAction(window,kAXRaiseAction)!=kAXErrorSuccess) NSBeep();
    }
    self.nextRefresh=0;
}
@end
// A brief grace period bridges the gap between icon and popup without keeping
// the shelf open after the pointer leaves both surfaces.
int hood_tooltip_active(void *tip) {
    HoodTooltip *w=(__bridge HoodTooltip *)tip;
    if(!w || !w.visible || !w.list) return 0;
    if(NSPointInRect(NSEvent.mouseLocation,NSInsetRect(w.frame,-8,-8))) w.lastInside=hood_time();
    return hood_time()-w.lastInside<0.35;
}
void *hood_tooltip_create(void) {
    HoodTooltip *w=[[HoodTooltip alloc] initWithContentRect:NSMakeRect(0,0,100,26) styleMask:NSWindowStyleMaskBorderless|NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:NO];
    w.hidesOnDeactivate=NO;
    w.becomesKeyOnlyIfNeeded=YES;
    w.releasedWhenClosed=NO; w.opaque=NO; w.backgroundColor=NSColor.clearColor; w.ignoresMouseEvents=YES;
    w.contentView.wantsLayer=YES; w.contentView.layer.cornerRadius=7; w.contentView.layer.masksToBounds=YES;
    w.contentView.layer.backgroundColor=[NSColor colorWithSRGBRed:54/255.0 green:54/255.0 blue:60/255.0 alpha:1].CGColor;
    NSTextField *label=[NSTextField labelWithString:@""];
    label.font=[NSFont fontWithName:@"WorkSans-Regular" size:12]?:[NSFont menuFontOfSize:12];
    label.textColor=NSColor.whiteColor;
    label.alignment=NSTextAlignmentCenter;
    label.lineBreakMode=NSLineBreakByWordWrapping;
    label.maximumNumberOfLines=0;
    label.cell.wraps=YES;
    label.cell.scrollable=NO;
    label.tag=1; [w.contentView addSubview:label];
    return (__bridge_retained void *)w;
}
void hood_tooltip_show(void *tip,void *shelf,const char *text,float cx,float cy,int edge,int opacityPercent,int pid) {
    HoodTooltip *w=(__bridge HoodTooltip *)tip;
    NSWindow *host=(__bridge NSWindow *)shelf;
    if(!host.screen) { [w orderOut:nil]; return; }
    CGFloat opacity=MAX(0.2,MIN(1.0,opacityPercent/100.0));
    w.contentView.layer.backgroundColor=[NSColor colorWithSRGBRed:54/255.0 green:54/255.0 blue:60/255.0 alpha:opacity].CGColor;
    NSTextField *label=(NSTextField *)[w.contentView viewWithTag:1];
    NSString *title=[NSString stringWithUTF8String:text];
    if(![label.stringValue isEqualToString:title]) label.stringValue=title;
    NSRect available=host.screen.visibleFrame, frame=host.frame;
    CGFloat maxWidth=available.size.width-16;
    if(edge<2) maxWidth-=frame.size.width+12;
    NSDictionary *attributes=@{NSFontAttributeName:label.font};
    CGFloat naturalWidth=ceil([title sizeWithAttributes:attributes].width);
    // NSTextField's cell uses a few extra pixels beyond NSString's reported
    // width. Leave horizontal slack, and measure wrapping conservatively so a
    // trailing character or second word cannot fall onto a clipped line.
    CGFloat maxContentWidth=MIN(360,MAX(80,maxWidth-20));
    CGFloat contentWidth=MIN(naturalWidth+12,maxContentWidth);
    CGFloat measuredWidth=MAX(1,contentWidth-8);
    NSRect textBounds=[title boundingRectWithSize:NSMakeSize(measuredWidth,CGFLOAT_MAX)
        options:NSStringDrawingUsesLineFragmentOrigin|NSStringDrawingUsesFontLeading attributes:attributes];
    CGFloat textHeight=MAX(16,ceil(textBounds.size.height));
    CGFloat width=MIN(maxWidth,contentWidth+20), height=textHeight+8;
    if(w.pid!=pid || !w.visible || hood_time()>=w.nextRefresh) {
        w.pid=pid; w.nextRefresh=hood_time()+1;
        NSMutableArray *windows=[NSMutableArray array];
        if(pid>0 && AXIsProcessTrusted()) {
            AXUIElementRef app=AXUIElementCreateApplication(pid);
            AXUIElementSetMessagingTimeout(app,0.15);
            id values=hood_ax_value(app,kAXWindowsAttribute);
            if([values isKindOfClass:NSArray.class]) {
                for(id value in values) {
                    // Some apps publish transient controls, such as Chromium's
                    // find bar, in AXWindows even though they are not windows.
                    if(hood_ax_standard_window((__bridge AXUIElementRef)value)) [windows addObject:value];
                }
            }
            CFRelease(app);
        }
        w.windows=windows;
        [w.list removeFromSuperview]; w.list=nil;
        BOOL needsAccess=pid>0 && !AXIsProcessTrusted();
        w.needsAccess=needsAccess;
        if(windows.count>1 || needsAccess) {
            w.list=[[NSScrollView alloc] initWithFrame:NSZeroRect];
            w.list.hasVerticalScroller=YES; w.list.drawsBackground=NO;
            w.list.autohidesScrollers=YES;
            w.list.scrollerStyle=NSScrollerStyleOverlay;
            NSView *rows=[[NSView alloc] initWithFrame:NSMakeRect(0,0,needsAccess?334:360,needsAccess?84:windows.count*36)];
            if(needsAccess) {
                NSTextField *help=[NSTextField wrappingLabelWithString:@"In Privacy & Security → Accessibility, enable Hood.\nIf missing, use + to add the app or executable."];
                help.font=[NSFont systemFontOfSize:12];
                help.textColor=NSColor.whiteColor;
                help.alignment=NSTextAlignmentCenter;
                help.frame=NSMakeRect(8,40,318,40);
                [rows addSubview:help];
                NSButton *button=[HoodPopupButton buttonWithTitle:@"Open Accessibility Settings" target:w action:@selector(enableAccess:)];
                button.frame=NSMakeRect(8,4,318,32); [rows addSubview:button];
                w.list.hasVerticalScroller=NO;
            } else for(NSUInteger i=0;i<windows.count;i++) {
                AXUIElementRef window=(__bridge AXUIElementRef)windows[i];
                id value=hood_ax_value(window,kAXTitleAttribute);
                NSString *name=[value isKindOfClass:NSString.class] && [value length]?value:@"Untitled window";
                CGFloat y=(windows.count-i-1)*36;
                NSButton *row=[HoodWindowButton buttonWithTitle:name target:w action:@selector(windowAction:)];
                row.tag=i; row.frame=NSMakeRect(4,y+2,352,32);
                row.alignment=NSTextAlignmentCenter;
                row.lineBreakMode=NSLineBreakByTruncatingTail;
                row.toolTip=name;
                [rows addSubview:row];
            }
            w.list.documentView=rows; [w.contentView addSubview:w.list];
        }
        w.ignoresMouseEvents=w.list==nil;
    }
    if(w.list) {
        width=MIN(maxWidth,w.needsAccess?350:320);
        height=MIN(available.size.height-16, textHeight+16+MIN(360,w.list.documentView.frame.size.height));
        w.list.frame=NSMakeRect(4,4,width-8,MAX(0,height-textHeight-12));
        if(!w.needsAccess) {
            // Match the dock's configured color exactly. Size rows from the
            // viewport, not a fixed document width, for equal side margins.
            w.contentView.layer.backgroundColor=((HoodPanel *)host).background.backgroundColor;
            w.list.frame=NSMakeRect(8,6,width-16,MAX(0,height-textHeight-16));
            NSView *rows=w.list.documentView;
            CGFloat rowWidth=w.list.contentSize.width;
            [rows setFrameSize:NSMakeSize(rowWidth,rows.frame.size.height)];
            NSColor *background=[NSColor colorWithCGColor:w.contentView.layer.backgroundColor];
            for(HoodWindowButton *row in rows.subviews) {
                row.popupColor=background;
                row.needsDisplay=YES;
                NSRect rowFrame=row.frame;
                rowFrame.origin.x=0;
                rowFrame.size.width=rowWidth;
                row.frame=rowFrame;
            }
        }
        w.lastInside=hood_time();
    }
    CGFloat gap=w.list && !w.needsAccess?2:6;
    CGFloat x=NSMaxX(frame)+gap, y=NSMaxY(frame)-cy-height/2;
    if(edge==1) x=NSMinX(frame)-width-gap;
    if(edge>=2) { x=NSMinX(frame)+cx-width/2; y=edge==2?NSMaxY(frame)+gap:NSMinY(frame)-height-gap; }
    x=MAX(NSMinX(available),MIN(x,NSMaxX(available)-width));
    y=MAX(NSMinY(available),MIN(y,NSMaxY(available)-height));
    NSRect target=NSMakeRect(x,y,width,height);
    if(!NSEqualRects(w.frame,target)) [w setFrame:target display:YES];
    label.textColor=hood_text_color([NSColor colorWithCGColor:w.contentView.layer.backgroundColor]);
    // Work Sans' visible glyphs sit slightly above the center of AppKit's
    // typographic line box. Lower the label by one point for optical centering.
    label.frame=NSMakeRect(10,w.list?height-textHeight-5:3,width-20,textHeight); w.level=host.level+1;
    if(!w.visible) [w orderFrontRegardless];
}

// NSScreen.screens starts with the primary display, unlike mainScreen which
// follows the key window. Keep a missing selection intact for reconnection.
void *hood_selected_screen(const char *selection, int32_t index) {
    NSArray<NSScreen *> *screens=NSScreen.screens;
    if(!screens.count) return NULL;
    if(strcmp(selection,"all")==0)
        return index>=0 && (NSUInteger)index<screens.count ? (__bridge void *)screens[index] : NULL;
    if(index!=0) return NULL;
    NSString *key=[NSString stringWithUTF8String:selection];
    for(NSScreen *screen in screens)
        if([hood_display_key(screen) caseInsensitiveCompare:key]==NSOrderedSame) return (__bridge void *)screen;
    return (__bridge void *)screens.firstObject;
}
uint32_t hood_screen_id(void *handle) {
    NSScreen *screen=(__bridge NSScreen *)handle;
    return [screen.deviceDescription[@"NSScreenNumber"] unsignedIntValue];
}
