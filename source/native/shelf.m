#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#include <stdint.h>
#include <time.h>

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
@end
@implementation HoodPanel
- (BOOL)canBecomeKeyWindow { return YES; }
@end

double hood_time(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC,&t); return t.tv_sec+t.tv_nsec/1e9; }
void *hood_create(void) {
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    [NSApp finishLaunching];
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
    HoodPanel *w=(__bridge HoodPanel *)handle;
    *input=(HoodInput){0};
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:wait];
    for (;;) {
        NSEvent *e=[NSApp nextEventMatchingMask:NSEventMaskAny untilDate:deadline inMode:NSDefaultRunLoopMode dequeue:YES];
        if(!e) break;
        deadline=NSDate.distantPast;
        if(e.window==w) {
            switch(e.type) {
                case NSEventTypeLeftMouseDown: input->pressed=1; break;
                case NSEventTypeLeftMouseUp: input->released=1; break;
                case NSEventTypeRightMouseUp: input->right=1; break;
                case NSEventTypeScrollWheel: input->wheel+=e.scrollingDeltaY/(e.hasPreciseScrollingDeltas?10:1); break;
                case NSEventTypeKeyDown: if(e.keyCode==53) input->escape=1; break;
                default: break;
            }
        }
        [NSApp sendEvent:e];
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
void *hood_tooltip_create(void) {
    NSWindow *w=[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,100,26) styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
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
void hood_tooltip_show(void *tip,void *shelf,const char *text,float cx,float cy,int edge,int opacityPercent) {
    NSWindow *w=(__bridge NSWindow *)tip, *host=(__bridge NSWindow *)shelf;
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
    CGFloat x=NSMaxX(frame)+6, y=NSMaxY(frame)-cy-height/2;
    if(edge==1) x=NSMinX(frame)-width-6;
    if(edge>=2) { x=NSMinX(frame)+cx-width/2; y=edge==2?NSMaxY(frame)+6:NSMinY(frame)-height-6; }
    x=MAX(NSMinX(available),MIN(x,NSMaxX(available)-width));
    y=MAX(NSMinY(available),MIN(y,NSMaxY(available)-height));
    NSRect target=NSMakeRect(x,y,width,height);
    if(!NSEqualRects(w.frame,target)) [w setFrame:target display:YES];
    label.frame=NSMakeRect(10,4,width-20,textHeight); w.level=host.level+1;
    if(!w.visible) [w orderFrontRegardless];
}
