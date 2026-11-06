#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>

static NSString *hood_display_key(NSScreen *screen) {
    CGDirectDisplayID display=[screen.deviceDescription[@"NSScreenNumber"] unsignedIntValue];
    CFUUIDRef uuid=CGDisplayCreateUUIDFromDisplayID(display);
    if(!uuid) return @"";
    NSString *key=CFBridgingRelease(CFUUIDCreateString(NULL,uuid));
    CFRelease(uuid);
    return key;
}
