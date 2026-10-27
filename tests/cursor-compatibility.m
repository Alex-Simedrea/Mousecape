#import <Cocoa/Cocoa.h>
#import "MCDefs.h"
#import "MCPrefs.h"
#import "apply.h"

// Exercise the real apply code without changing system cursors or preferences.
static NSMutableDictionary *registrations;
static CGError registrationError;
static NSString *appliedIdentifier;
NSString *MCPreferencesAppliedCursorKey = @"MCAppliedCursor";
NSString *MCPreferencesHandednessKey = @"MCHandedness";
CGSConnectionID CGSMainConnectionID(void) { return 0; }
void resetAllCursors(void) {}
void backupAllCursors(void) {}
id MCDefault(NSString *key) { return nil; }
void MCSetDefaultFor(id value, NSString *key, NSString *user, NSString *host) {
    appliedIdentifier = value;
}
CGError CGSRegisterCursorWithImages(CGSConnectionID cid, char *name, bool global,
    bool instantly, CGSize size, CGPoint hotspot, NSUInteger frames,
    CGFloat duration, CFArrayRef images, int *seed) {
    registrations[@(name)] = @{
        @"frames": @(frames), @"duration": @(duration),
        @"width": @(size.width), @"height": @(size.height),
        @"hotspot": [NSValue valueWithPoint:hotspot], @"images": (__bridge NSArray *)images
    };
    return registrationError;
}

static NSDictionary *cursor(NSUInteger frames, NSUInteger frameHeight) {
    NSMutableArray *images = [NSMutableArray array];
    for (NSUInteger scale = 1; scale <= 2; scale++) {
        NSBitmapImageRep *image = [[[NSBitmapImageRep alloc]
            initWithBitmapDataPlanes:NULL pixelsWide:2 * scale
            pixelsHigh:frameHeight * frames * scale bitsPerSample:8
            samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace
            bytesPerRow:0 bitsPerPixel:32] autorelease];
        for (NSUInteger y = 0; y < image.pixelsHigh; y++) {
            for (NSUInteger x = 0; x < image.pixelsWide; x++) {
                unsigned char *pixel = image.bitmapData + y * image.bytesPerRow + x * 4;
                pixel[0] = (unsigned char)(y / (frameHeight * scale));
                pixel[1] = pixel[2] = 0;
                pixel[3] = 255;
            }
        }
        [images addObject:[image TIFFRepresentation]];
    }
    return @{@"FrameCount": @(frames), @"FrameDuration": @0.01,
        @"PointsWide": @2, @"PointsHigh": @(frameHeight), @"HotSpotX": @1,
        @"HotSpotY": @1, @"Representations": images};
}

int main(void) {
    @autoreleasepool {
        registrations = [NSMutableDictionary dictionary];
        NSString *arrow = @"com.apple.coregraphics.Arrow";
        NSString *arrowS = @"com.apple.coregraphics.ArrowS";
        NSString *ibeam = @"com.apple.coregraphics.IBeam";
        NSString *ibeamS = @"com.apple.coregraphics.IBeamS";
        NSDictionary *cursors = @{arrow: cursor(1, 2), ibeam: cursor(1, 3),
            @"com.apple.coregraphics.IBeamXOR": cursor(1, 4)};
        NSDictionary *cape = @{@"Cursors": cursors, @"CapeName": @"Test",
            @"CapeVersion": @1, @"Identifier": @"test.compatibility"};
        NSCAssert(applyCape(cape), @"Legacy cape should apply");
        NSCAssert(registrations[arrowS] && registrations[ibeamS], @"Missing compatibility alias");
        NSCAssert([registrations[arrowS][@"height"] isEqual:@2], @"Arrow alias differs");
        NSCAssert([registrations[ibeamS][@"height"] isEqual:@3], @"IBeamXOR replaced primary text cursor");
        NSCAssert(!cursors[arrowS] && !cursors[ibeamS], @"Input cape was modified");
        NSCAssert([appliedIdentifier isEqual:@"test.compatibility"], @"Successful cape not recorded");

        NSMutableDictionary *explicitCursors = [[cursors mutableCopy] autorelease];
        explicitCursors[arrowS] = cursor(1, 5);
        explicitCursors[ibeamS] = cursor(1, 6);
        NSMutableDictionary *explicitCape = [[cape mutableCopy] autorelease];
        explicitCape[@"Cursors"] = explicitCursors;
        NSCAssert(applyCape(explicitCape), @"Explicit aliases should apply");
        NSCAssert([registrations[arrowS][@"height"] isEqual:@5], @"Explicit arrow alias overwritten");
        NSCAssert([registrations[ibeamS][@"height"] isEqual:@6], @"Explicit IBeam alias overwritten");

        NSCAssert(applyCapeForIdentifier(cursor(30, 2), @"test.animation", NO), @"30-frame cursor rejected");
        NSDictionary *animation = registrations[@"test.animation"];
        NSCAssert([animation[@"frames"] isEqual:@24], @"Wrong output frame count");
        NSCAssert(fabs([animation[@"duration"] doubleValue] * 24 - 0.3) < 0.000001, @"Animation duration changed");
        NSArray *images = animation[@"images"];
        NSCAssert(images.count == 2, @"Image scales lost");
        for (NSUInteger scale = 1; scale <= 2; scale++) {
            CGImageRef image = (__bridge CGImageRef)images[scale - 1];
            NSCAssert(CGImageGetWidth(image) == 2 * scale && CGImageGetHeight(image) == 48 * scale,
                @"Animation dimensions changed incorrectly");
            CFDataRef pixels = CGDataProviderCopyData(CGImageGetDataProvider(image));
            const UInt8 *bytes = CFDataGetBytePtr(pixels);
            for (NSUInteger frame = 0; frame < 24; frame++) {
                NSUInteger offset = frame * 2 * scale * CGImageGetBytesPerRow(image);
                NSCAssert(bytes[offset] == frame * 30 / 24, @"Animation frames reordered or flipped");
                NSCAssert(bytes[offset + 3] == 255, @"Animation alpha lost");
            }
            CFRelease(pixels);
        }
        NSCAssert(!applyCursorForIdentifier(0, 0, CGPointZero, CGSizeZero, @[], @"test.invalid", 0), @"Zero frames accepted");
        registrationError = kCGErrorFailure;
        appliedIdentifier = nil;
        NSCAssert(!applyCape(cape), @"Registration failure ignored");
        NSCAssert(appliedIdentifier == nil, @"Failed cape recorded as applied");

        NSArray *defaultNames = @[@"com.apple.coregraphics.ArrowS", @"com.apple.coregraphics.IBeamS"];
        for (NSString *name in defaultNames) {
            BOOL found = NO;
            for (NSUInteger i = 0; defaultCursors[i]; i++) {
                found |= [defaultCursors[i] isEqual:name];
            }
            NSCAssert(found, @"Modern cursor missing from backup/reset/dump list");
        }
        NSCAssert(MCCursorIsPointer(arrowS), @"Modern arrow missing left-handed support");
        puts("Cursor compatibility tests passed");
    }
}
