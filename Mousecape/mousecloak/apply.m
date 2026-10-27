//
//  apply.m
//  Mousecape
//
//  Created by Alex Zielenski on 2/1/14.
//  Copyright (c) 2014 Alex Zielenski. All rights reserved.
//

#import "create.h"
#import "backup.h"
#import "restore.h"
#import "MCPrefs.h"
#import "NSBitmapImageRep+ColorSpace.h"

BOOL applyCursorForIdentifier(NSUInteger frameCount, CGFloat frameDuration, CGPoint hotSpot, CGSize size, NSArray *images, NSString *ident, NSUInteger repeatCount) {
    if (frameCount < 1) {
        MMLog(BOLD RED "Frame count of %s must be at least 1" RESET, ident.UTF8String);
        return NO;
    }

    // WindowServer exports 30-frame system cursors but still rejects registering
    // more than 24 frames. Sample the whole animation, preserving its duration
    // and every image scale, rather than aborting the rest of the cape.
    const NSUInteger maxFrames = 24;
    if (frameCount > maxFrames) {
        NSMutableArray *sampledImages = [NSMutableArray arrayWithCapacity:images.count];
        for (id object in images) {
            CGImageRef image = (__bridge CGImageRef)object;
            size_t width = CGImageGetWidth(image);
            size_t height = CGImageGetHeight(image);
            if (height < frameCount || height % frameCount != 0) {
                MMLog(BOLD RED "Invalid animation image for %s" RESET, ident.UTF8String);
                return NO;
            }
            size_t frameHeight = height / frameCount;
            CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
            CGContextRef context = CGBitmapContextCreate(NULL, width, frameHeight * maxFrames,
                8, 0, colorSpace, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
            CGColorSpaceRelease(colorSpace);
            if (!context) return NO;
            CGContextSetBlendMode(context, kCGBlendModeCopy);
            for (NSUInteger frame = 0; frame < maxFrames; frame++) {
                NSUInteger sourceFrame = frame * frameCount / maxFrames;
                CGImageRef slice = CGImageCreateWithImageInRect(image,
                    CGRectMake(0, sourceFrame * frameHeight, width, frameHeight));
                if (!slice) {
                    CGContextRelease(context);
                    return NO;
                }
                CGContextDrawImage(context,
                    CGRectMake(0, (maxFrames - frame - 1) * frameHeight, width, frameHeight), slice);
                CGImageRelease(slice);
            }
            CGImageRef sampled = CGBitmapContextCreateImage(context);
            CGContextRelease(context);
            if (!sampled) return NO;
            [sampledImages addObject:(__bridge id)sampled];
            CGImageRelease(sampled);
        }
        MMLog("Sampling %s from %lu to %lu frames", ident.UTF8String,
            (unsigned long)frameCount, (unsigned long)maxFrames);
        images = sampledImages;
        frameDuration *= (CGFloat)frameCount / maxFrames;
        frameCount = maxFrames;
    }

    char *idenfifier = (char *)ident.UTF8String;
    int seed = 0;
    CGError err = CGSRegisterCursorWithImages(CGSMainConnectionID(),
                                              idenfifier,
                                              true,
                                              true,
                                              size,
                                              hotSpot,
                                              frameCount,
                                              frameDuration,
                                              (__bridge CFArrayRef)images,
                                              &seed);
    
    if (err != kCGErrorSuccess) {
        MMLog(BOLD RED "Could not register %s: CGError %d" RESET, ident.UTF8String, err);
    }
    return (err == kCGErrorSuccess);
}

BOOL applyCapeForIdentifier(NSDictionary *cursor, NSString *identifier, BOOL restore) {
    if (!cursor || !identifier) {
        NSLog(@"bad seed");
        return NO;
    }

    BOOL lefty = MCFlag(MCPreferencesHandednessKey);
    BOOL pointer = MCCursorIsPointer(identifier);
    NSNumber *frameCount    = cursor[MCCursorDictionaryFrameCountKey];
    NSNumber *frameDuration = cursor[MCCursorDictionaryFrameDuratiomKey];
    //    NSNumber *repeatCount   = cursor[MCCursorDictionaryRepeatCountKey];
    
    CGPoint hotSpot         = CGPointMake([cursor[MCCursorDictionaryHotSpotXKey] doubleValue],
                                          [cursor[MCCursorDictionaryHotSpotYKey] doubleValue]);
    CGSize size             = CGSizeMake([cursor[MCCursorDictionaryPointsWideKey] doubleValue],
                                         [cursor[MCCursorDictionaryPointsHighKey] doubleValue]);
    NSArray *reps           = cursor[MCCursorDictionaryRepresentationsKey];
    NSMutableArray *images  = [NSMutableArray array];

    if (lefty && !restore && pointer) {
        MMLog("Lefty mode for %s", identifier.UTF8String);
        hotSpot.x = size.width - hotSpot.x - 1;
    }

    for (id object in reps) {
        CFTypeID type = CFGetTypeID((__bridge CFTypeRef)object);
        NSBitmapImageRep *rep;
        if (type == CGImageGetTypeID()) {
            rep = [[[NSBitmapImageRep alloc] initWithCGImage:(__bridge CGImageRef)object] autorelease];
        } else {
            rep = [[[NSBitmapImageRep alloc] initWithData:object] autorelease];
        }
        rep = rep.retaggedSRGBSpace;

        if (!lefty || restore || !pointer) {
            // special case if array has a type of CGImage already there is no need to convert it
            if (type == CGImageGetTypeID()) {
                images[images.count] = object;
                continue;
            }
            
            images[images.count] = (__bridge id)[rep CGImage];
            
        } else {
            NSBitmapImageRep *newRep = [[[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                               pixelsWide:rep.pixelsWide
                                                                               pixelsHigh:rep.pixelsHigh
                                                                            bitsPerSample:8
                                                                          samplesPerPixel:4
                                                                                 hasAlpha:YES
                                                                                 isPlanar:NO
                                                                           colorSpaceName:NSCalibratedRGBColorSpace
                                                                              bytesPerRow:4 * rep.pixelsWide
                                                                             bitsPerPixel:32] autorelease];
            NSGraphicsContext *ctx = [NSGraphicsContext graphicsContextWithBitmapImageRep:newRep];
            [NSGraphicsContext saveGraphicsState];
            [NSGraphicsContext setCurrentContext:ctx];
            NSAffineTransform *transform = [NSAffineTransform transform];
            [transform translateXBy:rep.pixelsWide yBy:0];
            [transform scaleXBy:-1 yBy:1];
            [transform concat];

            [rep drawInRect:NSMakeRect(0, 0, rep.pixelsWide, rep.pixelsHigh)
                   fromRect:NSZeroRect
                  operation:NSCompositingOperationSourceOver
                   fraction:1.0
             respectFlipped:NO
                      hints:nil];
            [NSGraphicsContext restoreGraphicsState];
            images[images.count] = (__bridge id)[newRep CGImage];
        }
    }
    
    return applyCursorForIdentifier(frameCount.unsignedIntegerValue, frameDuration.doubleValue, hotSpot, size, images, identifier, 0);
}

BOOL applyCape(NSDictionary *dictionary) {
    @autoreleasepool {
        NSMutableDictionary *cursors = [[dictionary[MCCursorDictionaryCursorsKey] mutableCopy] autorelease];
        // Newer macOS versions also use these names for the primary arrow and
        // text cursor. Fill missing aliases without changing the cape on disk
        // or overriding an explicitly supplied alias. Do not alias ArrowCtx or
        // IBeamXOR: those can contain different artwork, including empty images.
        NSDictionary *aliases = @{
            @"com.apple.coregraphics.ArrowS": @"com.apple.coregraphics.Arrow",
            @"com.apple.coregraphics.IBeamS": @"com.apple.coregraphics.IBeam"
        };
        for (NSString *alias in aliases) {
            if (!cursors[alias] && cursors[aliases[alias]]) {
                cursors[alias] = cursors[aliases[alias]];
            }
        }
        NSString *name = dictionary[MCCursorDictionaryCapeNameKey];
        NSNumber *version = dictionary[MCCursorDictionaryCapeVersionKey];
        
        resetAllCursors();
        backupAllCursors();
        
        MMLog("Applying cape: %s %.02f", name.UTF8String, version.floatValue);
        
        for (NSString *key in cursors) {
            NSDictionary *cape = cursors[key];
            MMLog("Hooking for %s", key.UTF8String);
            
            BOOL success = applyCapeForIdentifier(cape, key, NO);
            if (!success) {
                MMLog(BOLD RED "Failed to hook identifier %s for some unknown reason. Bailing out..." RESET, key.UTF8String);
                return NO;
            }
        }
        
        MCSetDefault(dictionary[MCCursorDictionaryIdentifierKey], MCPreferencesAppliedCursorKey);
        
        MMLog(BOLD GREEN "Applied %s successfully!" RESET, name.UTF8String);
        
        return YES;
    }
}

BOOL applyCapeAtPath(NSString *path) {
    NSDictionary *cape = [NSDictionary dictionaryWithContentsOfFile:path];
    if (cape)
        return applyCape(cape);
    MMLog(BOLD RED "Could not find valid file at %s to apply" RESET, path.UTF8String);
    return NO;
}
