#import <AppKit/AppKit.h>
#include <stdio.h>

// Launch through LaunchServices so Hood is an independent app for macOS privacy
// attribution. Return its actual PID so the watcher can stop only this instance.
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if(argc!=3) { fprintf(stderr,"Usage: hood-launch APP_PATH MANIFEST_PATH\n"); return 1; }
        NSURL *url=[NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]];
        NSWorkspaceOpenConfiguration *configuration=[NSWorkspaceOpenConfiguration configuration];
        configuration.createsNewApplicationInstance=YES;
        configuration.activates=NO;
        NSMutableDictionary *environment=[NSProcessInfo.processInfo.environment mutableCopy];
        environment[@"HOOD_UI_MANIFEST"]=[NSString stringWithUTF8String:argv[2]];
        configuration.environment=environment;
        __block BOOL finished=NO;
        __block int result=1;
        [NSWorkspace.sharedWorkspace openApplicationAtURL:url configuration:configuration
            completionHandler:^(NSRunningApplication *app, NSError *error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if(error || !app) {
                        fprintf(stderr,"Could not launch Hood: %s\n",error.localizedDescription.UTF8String ?: "unknown error");
                    } else {
                        printf("%d\n",app.processIdentifier);
                        result=0;
                    }
                    finished=YES;
                });
            }];
        while(!finished) {
            [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        }
        return result;
    }
}
