//
//  YZHookHandler.h
//  YZHookHandler
//
//  Created by zhiqiang_ye on 2020/11/7.
//  Copyright © 2020 CancerQ. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
extern NSErrorDomain const YZHookHandlerErrorDomain;
typedef NS_ERROR_ENUM(YZHookHandlerErrorDomain, YZHookHandlerSelectorError) {
    /// -yz_hookForSelector: was going to add a new method implementation for
    /// `selector`, but another thread added an implementation before it was able to.
    ///
    /// This will _not_ occur for cases where a method implementation exists before
    /// -yz_hookForSelector: is invoked.
    YZHookHandlerSelectorErrorMethodSwizzlingRace = 1,
};

typedef void(^YZHookArgsBlock)(NSArray *args);

/**
YZHookHandler uses Objective-C message forwarding to hook into messages. This will create some overhead. Don't add hook to methods that are called a lot. YZHookHandler is meant for view/controller code that is not called a 1000 times per second.

Adding hook returns a handler which can be used to deregister again. All calls are thread safe.
*/
@interface YZHookHandler : NSObject
+ (instancetype)new NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

/// Called after the original implementation
- (YZHookHandler *)after:(YZHookArgsBlock)after;
/// Will replace the original implementation.
- (YZHookHandler *)instead:(YZHookArgsBlock)instead;
/// Called before the original implementation.
- (YZHookHandler *)befor:(YZHookArgsBlock)befor;
///Remove the current hook.
- (void)removeHook;

@end

@interface NSObject (YZHookHandler)
///Hook selector alias prefix, default is yz_alias.
@property (class, nonatomic, copy) NSString *yz_hookHandlerForSelectorAliasPrefix;
///Swizzle subclass suffix, default is _YZHookHandler.
@property (class, nonatomic, copy) NSString *yz_subclassSuffix;

/// This is useful for changing an event or delegate callback into a handler. For
/// example, on an UIViewController:
///
///     [[viewController yz_hookForSelector:@selector(viewWillAppear:)] after:^(NSArray * _Nonnull args) {
///         BOOL animated = args[0];
///         NSLog(@"viewWillAppear: %d", animated);
///     }];
///
/// selector - The selector for whose invocations are to be observed. If it
///            doesn't exist, it will be implemented to accept object arguments
///            and return void. This cannot have C arrays or unions as arguments
///            or C arrays, unions, structs, complex or vector types as return
///            type.
/// Returns a hook handler. If a runtime call fails, the handler will send an error for
/// YZHookHandlerErrorDomain.
- (YZHookHandler *)yz_hookForSelector:(SEL)selector;

/// Behaves like -yz_hookForSelector:, but if the selector is not yet
/// implemented on the receiver, its method signature is looked up within
/// `protocol`, and may accept non-object arguments.
///
/// If the selector is not yet implemented and has a return value, the injected
/// method will return all zero bits (equal to `nil`, `NULL`, 0, 0.0f, etc.).
///
/// selector - The selector for whose invocations are to be observed. If it
///            doesn't exist, it will be implemented using information from
///            `protocol`, and may accept non-object arguments and return
///            a value. This cannot have C arrays or unions as arguments or
///            return type.
/// protocol - The protocol in which `selector` is declared. This will be used
///            for type information if the selector is not already implemented on
///            the receiver. This must not be `NULL`, and `selector` must exist
///            in this protocol.
///
/// Returns a hook handler. If a runtime call fails, the handler will send an error for
/// YZHookHandlerErrorDomain.
- (YZHookHandler *)yz_hookForSelector:(SEL)selector fromProtocol:(Protocol *)protocol;
///Remove all hooks.
- (void)yz_removeAllHooks;

@end

NS_ASSUME_NONNULL_END
