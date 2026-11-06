#import <AppKit/AppKit.h>

// Vector artwork rendered at every native macOS icon size.
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if(argc!=2) return 1;
        NSString *directory=[NSString stringWithUTF8String:argv[1]];
        for(NSNumber *base in @[@16,@32,@128,@256,@512]) {
            for(int scale=1;scale<=2;scale++) {
                int pixels=base.intValue*scale;
                NSBitmapImageRep *bitmap=[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:pixels pixelsHigh:pixels bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
                [NSGraphicsContext saveGraphicsState];
                [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap]];
                NSAffineTransform *transform=[NSAffineTransform transform];
                [transform scaleBy:pixels/1024.0]; [transform concat];
                NSBezierPath *tile=[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(64,64,896,896) xRadius:200 yRadius:200];
                NSGradient *gradient=[[NSGradient alloc] initWithStartingColor:[NSColor colorWithSRGBRed:0.20 green:0.28 blue:0.39 alpha:1] endingColor:[NSColor colorWithSRGBRed:0.07 green:0.10 blue:0.17 alpha:1]];
                [gradient drawInBezierPath:tile angle:-90];
                [[NSColor colorWithWhite:1 alpha:0.18] setStroke]; tile.lineWidth=8; [tile stroke];
                // A bright H above a three-tile shelf stays legible at Dock size.
                [[NSColor colorWithSRGBRed:0.88 green:0.94 blue:1 alpha:1] setFill];
                for(NSValue *rect in @[[NSValue valueWithRect:NSMakeRect(300,420,100,350)], [NSValue valueWithRect:NSMakeRect(624,420,100,350)], [NSValue valueWithRect:NSMakeRect(380,550,264,90)]]) {
                    [[NSBezierPath bezierPathWithRoundedRect:rect.rectValue xRadius:24 yRadius:24] fill];
                }
                [[NSColor colorWithWhite:1 alpha:0.13] setFill];
                [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(190,210,644,154) xRadius:48 yRadius:48] fill];
                NSArray *colors=@[[NSColor colorWithSRGBRed:0.25 green:0.79 blue:0.92 alpha:1], [NSColor colorWithSRGBRed:0.57 green:0.52 blue:0.95 alpha:1], [NSColor colorWithSRGBRed:0.98 green:0.69 blue:0.35 alpha:1]];
                for(int i=0;i<3;i++) {
                    [colors[i] setFill];
                    [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(272+i*180,242,120,90) xRadius:22 yRadius:22] fill];
                }
                [NSGraphicsContext restoreGraphicsState];
                NSString *name=[NSString stringWithFormat:@"icon_%dx%d%@.png",base.intValue,base.intValue,scale==2?@"@2x":@""];
                NSData *png=[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
                if(![png writeToFile:[directory stringByAppendingPathComponent:name] atomically:YES]) return 1;
            }
        }
    }
    return 0;
}
