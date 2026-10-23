//
//  NSObject+PrivateSwizzle.m
//  PlayTools
//
//  Created by siri on 06.10.2021.
//

#import "NSObject+Swizzle.h"
#import <objc/runtime.h>
#import "CoreGraphics/CoreGraphics.h"
#import "UIKit/UIKit.h"
#import <PlayTools/PlayTools-Swift.h>
#import "PTFakeMetaTouch.h"
#import <VideoSubscriberAccount/VideoSubscriberAccount.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMotion/CoreMotion.h>
#import <GameController/GameController.h>

__attribute__((visibility("hidden")))
@interface PTSwizzleLoader : NSObject
@end

@implementation NSObject (Swizzle)

// Report an installation result to the hook diagnostics registry
static void PTRecordHook(Class cls, SEL origSelector, SEL newSelector,
                         NSString *result, NSString *detail) {
    [[HookStatusRegistry shared] recordTarget:NSStringFromClass(cls)
                                     selector:NSStringFromSelector(origSelector)
                                  replacement:NSStringFromSelector(newSelector)
                                       result:result
                                       detail:detail];
}

// Self-contained installer used by HookRegistry.swift. Mirrors the semantics
// of the former category helpers: `instance`/`classMethod` use the
// add-then-replace dance (safe when the original lives on a superclass),
// `exchange` swaps implementations in place (FBSSceneSettingsCore case).
BOOL PTSwizzleOnClassNamed(NSString *className,
                           PTSwizzleKind kind,
                           SEL origSelector,
                           SEL newSelector) {
    Class cls = objc_getClass(className.UTF8String);
    if (cls == Nil) {
        [[HookStatusRegistry shared] recordTarget:className
                                         selector:NSStringFromSelector(origSelector)
                                      replacement:NSStringFromSelector(newSelector)
                                           result:@"classNotFound"
                                           detail:@"class does not exist"];
        return NO;
    }

    // Class methods live on the metaclass; operate there directly so the
    // add/replace dance targets the right owner.
    Class owner = (kind == PTSwizzleKindClassMethod) ? object_getClass(cls) : cls;
    Method originalMethod = class_getInstanceMethod(owner, origSelector);
    Method swizzledMethod = class_getInstanceMethod(owner, newSelector);

    if (originalMethod == NULL || swizzledMethod == NULL) {
        PTRecordHook(cls, origSelector, newSelector,
                     @"failed", originalMethod == NULL
                         ? @"original method not found" : @"replacement method not found");
        return NO;
    }

    if (kind == PTSwizzleKindExchange) {
        method_exchangeImplementations(originalMethod, swizzledMethod);
    } else if (class_addMethod(owner,
                               origSelector,
                               method_getImplementation(swizzledMethod),
                               method_getTypeEncoding(swizzledMethod))) {
        // Added if selector did not exist on this class (inherited from super)
        class_replaceMethod(owner,
                            newSelector,
                            method_getImplementation(originalMethod),
                            method_getTypeEncoding(originalMethod));
    } else {
        class_replaceMethod(owner,
                            newSelector,
                            class_replaceMethod(owner,
                                                origSelector,
                                                method_getImplementation(swizzledMethod),
                                                method_getTypeEncoding(swizzledMethod)),
                            method_getTypeEncoding(originalMethod));
    }
    PTRecordHook(cls, origSelector, newSelector, @"applied", nil);
    return YES;
}

- (BOOL) hook_prefersPointerLocked {
    return false;
}

- (CGRect) hook_frameDefault {
    return [PlayScreen frameDefault:[self hook_frameDefault]];
}

- (CGRect) hook_boundsDefault {
    return [PlayScreen boundsDefault:[self hook_boundsDefault]];
}

- (CGRect) hook_nativeBoundsDefault {
    return [PlayScreen nativeBoundsDefault:[self hook_nativeBoundsDefault]];
}

- (CGSize) hook_sizeDelfault {
    return [PlayScreen sizeAspectRatioDefault:[self hook_sizeDelfault]];
}


- (CGRect) hook_frame {
    return [PlayScreen frame:[self hook_frame]];
}

- (CGRect) hook_bounds {
    return [PlayScreen bounds:[self hook_bounds]];
}

- (CGRect) hook_nativeBounds {
    return [PlayScreen nativeBounds:[self hook_nativeBounds]];
}

- (CGSize) hook_size {
    return [PlayScreen sizeAspectRatio:[self hook_size]];
}



- (long long) hook_orientation {
    return 0;
}

- (double) hook_nativeScale {
    return [[PlaySettings shared] customScaler];
}

- (double) hook_scale {
    // Return rounded value of [[PlaySettings shared] customScaler]
    // Even though it is a double return, this will only accept .0 value or apps will crash
    return round([[PlaySettings shared] customScaler]);
}

- (CGRect) hook_boundsResizable {
    return [PlayScreen boundsResizable:[self hook_boundsResizable]];
}

- (BOOL) hook_requiresFullScreen {
    return NO;
}

- (void) hook_setCurrentSubscription:(VSSubscription *)currentSubscription {
    // do nothing
}

- (NSString *)hook_stringByReplacingOccurrencesOfRegularExpressionPattern:(NSString *)pattern
                                                             withTemplate:(NSString *)template
                                                                  options:(NSRegularExpressionOptions)options
                                                                    range:(NSRange)range {
    // If the string is empty, return immediately to prevent a range out-of-bounds error.
    if ([(NSString*)self isEqualToString:@""]) {
        return @"";
    }
    return [self hook_stringByReplacingOccurrencesOfRegularExpressionPattern:pattern
                                                                withTemplate:template
                                                                     options:options
                                                                       range:range];
}

- (void)hook_requestRecordPermission:(void (^)(BOOL))response {
    BOOL granted = [[AVAudioSession sharedInstance] recordPermission] == AVAudioSessionRecordPermissionGranted;
    if (granted) {
        response(granted);
    } else {
        [self hook_requestRecordPermission:response];
    }
}

- (instancetype)hook_CMMotionManager_init {
    CMMotionManager *motionManager = (CMMotionManager *)[self hook_CMMotionManager_init];
    // The default update interval is 0, which may lead to excessive CPU usage
    motionManager.accelerometerUpdateInterval = 0.01;
    motionManager.deviceMotionUpdateInterval = 0.01;
    motionManager.gyroUpdateInterval = 0.01;
    return motionManager;
}

+ (GCMouse *)hook_GCMouse_current {
    return nil;
}

+ (NSArray *)hook_GCMouse_mice {
    return @[];
}

+ (void)hook_Unity_KeyboardDelegate_Initialize {
    @try {
        [self hook_Unity_KeyboardDelegate_Initialize];
    }
    @catch (NSException *exception) {
        [[PCLog loader] error:[NSString stringWithFormat:@"Unity KeyboardDelegate Initialize threw %@: %@",
                               exception.name, exception.reason]];
    }
}

// Hook for UIUserInterfaceIdiom

// - (long long) hook_userInterfaceIdiom {
//     return UIUserInterfaceIdiomPad;
// }

bool menuWasCreated = false;
- (id) initWithRootMenuHook:(id)rootMenu {
    self = [self initWithRootMenuHook:rootMenu];
    if (!menuWasCreated) {
        [PlayCover initMenuWithMenu: self];
        menuWasCreated = TRUE;
    }
    return self;
}

@end

/*
 This class only exists to apply swizzles from the +load of a class that won't have any categories/extensions. The reason
 for not doing this in a C module initializer is that obj-c initialization happens before any __attribute__((constructor))
 is called. This way we can guarantee the hooks will be applied before [PlayCover launch] is called (in PlayLoader.m).
 
 Side note:
 While adding method replacements to NSObject does work, I'm not certain this doesn't (or won't) have any side effects. The
 way Apple does method swizzling internally is by creating a category of the swizzled class and adding the replacements there.
 This keeps all those replacements "local" to that class. Example:
 
 '''
 @interface FBSSceneSettings (Swizzle)
 -(CGRect) hook_frame {
    ...
 }
 @end
 
 Somewhere else:
 swizzle(FBSSceneSettings.class, @selector(frame), @selector(hook_frame);
 '''
 
 However, doing this would require generating @interface declarations (either with class-dump or by hand) which would add a lot
 of code and complexity. I'm not sure this trade-off is "worth it", at least at the time of writing.
 */

@implementation PTSwizzleLoader
+ (void)load {
    // The entire install matrix now lives in HookRegistry.swift (declarative
    // specs + introspection-first installer). Same hooks for the same settings
    // matrix; safe mode and per-hook diagnostics handled by the registry.
    [HookRegistry installFromLoad];
}

@end
