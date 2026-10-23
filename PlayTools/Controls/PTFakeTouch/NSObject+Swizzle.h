//
//  NSObject+PrivateSwizzle.h
//  PlayTools
//
//  Created by siri on 06.10.2021.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, PTSwizzleKind) {
    PTSwizzleKindInstance = 0,
    PTSwizzleKindExchange = 1,
    PTSwizzleKindClassMethod = 2,
};

/// Self-contained swizzle bridge for HookRegistry.swift. Looks the class up by
/// name, probes the selector, installs the replacement and reports the result
/// to HookStatusRegistry. Returns NO when the class or the original method
/// cannot be found. Deliberately does NOT call the NSObject category helpers:
/// their selector is duplicated across several categories, so which
/// implementation would run is undefined.
FOUNDATION_EXPORT BOOL PTSwizzleOnClassNamed(NSString *className,
                                             PTSwizzleKind kind,
                                             SEL origSelector,
                                             SEL newSelector);

@interface NSObject (Swizzle)

@end

NS_ASSUME_NONNULL_END
