// Run with: clang -fobjc-arc -framework AppKit -framework QuartzCore
// -framework ApplicationServices tests/displays.m -o /tmp/hood-display-tests
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <objc/runtime.h>
#include <assert.h>

static CFUUIDRef test_display_uuid(CGDirectDisplayID display) {
    NSString *value=[NSString stringWithFormat:@"00000000-0000-0000-0000-%012u",display];
    return CFUUIDCreateFromString(NULL,(__bridge CFStringRef)value);
}
#define CGDisplayCreateUUIDFromDisplayID test_display_uuid
#import "../source/native/shelf.m"

@interface TestScreen : NSScreen
@property uint32_t identifier;
@end
@implementation TestScreen
- (NSDictionary *)deviceDescription { return @{@"NSScreenNumber":@(self.identifier)}; }
@end

static NSArray *connected;
static id test_screens(id receiver, SEL selector) {
    (void)receiver; (void)selector;
    return connected;
}

int main(void) {
    @autoreleasepool {
        Method method=class_getClassMethod(NSScreen.class,@selector(screens));
        IMP original=method_setImplementation(method,(IMP)test_screens);
        TestScreen *primary=[TestScreen new]; primary.identifier=1;
        TestScreen *external=[TestScreen new]; external.identifier=2;
        const char *selection="00000000-0000-0000-0000-000000000002";
        connected=@[primary,external];
        assert(hood_selected_screen("",0)==(__bridge void *)primary);
        assert(hood_selected_screen("",1)==NULL);
        assert(hood_selected_screen("all",0)==(__bridge void *)primary);
        assert(hood_selected_screen("all",1)==(__bridge void *)external);
        assert(hood_selected_screen("all",2)==NULL);
        assert(hood_selected_screen(selection,0)==(__bridge void *)external);
        assert(hood_selected_screen(selection,1)==NULL);
        // Disconnect, change primary, and reconnect without changing the preference.
        connected=@[primary];
        assert(hood_selected_screen(selection,0)==(__bridge void *)primary);
        assert(hood_selected_screen("all",1)==NULL);
        connected=@[external,primary];
        assert(hood_selected_screen(selection,0)==(__bridge void *)external);
        assert(hood_selected_screen("",0)==(__bridge void *)external);
        connected=@[];
        assert(hood_selected_screen(selection,0)==NULL);
        assert(hood_selected_screen("all",0)==NULL);
        method_setImplementation(method,original);
        puts("Display selection, disconnect fallback, reconnection, and empty topology passed.");
    }
}
