//
//  YZHookHandler.m
//  YZHookHandler <https://github.com/CancerQ/YZHookHandler>
//
//  Created by zhiqiang_ye on 2020/11/7.
//  Copyright © 2020 CancerQ. All rights reserved.
//

#import "YZHookHandler.h"
#import <objc/runtime.h>
#import <objc/message.h>

NSErrorDomain const YZHookHandlerErrorDomain = @"YZHookHandlerErrorDomain";
static NSString *const YZHookHandlerForSelectorAliasPrefix = @"yz_alias_";
static NSString *const YZSubclassSuffix = @"_YZHookHandler";

static NSString *_yz_hookHandlerForSelectorAliasPrefix = YZHookHandlerForSelectorAliasPrefix;
static NSString *_yz_subclassSuffix = YZSubclassSuffix;
static void *YZSubclassAssociationKey = &YZSubclassAssociationKey;
static void *YZAllSelectorsAssociationKey = &YZAllSelectorsAssociationKey;

@interface YZHookHandler ()
@property (nonatomic, weak) NSMutableArray<YZHookHandler *> *handlers;
@property (nonatomic, weak) id target;
@property (nonatomic, weak) Protocol *protocol;
@property (nonatomic) SEL selector;
@property (nonatomic, copy) YZHookArgsBlock after;
@property (nonatomic, copy) YZHookArgsBlock instead;
@property (nonatomic, copy) YZHookArgsBlock befor;
@property (nonatomic, strong) NSError *error;
- (instancetype)initWithError:(NSError *)error;
- (instancetype)initWithHookTarget:(id)target forSelector:(SEL)selector;
- (instancetype)initWithHookTarget:(id)target forSelector:(SEL)selector fromProtocol:(Protocol *)protocol;
@end

static NSMutableSet *swizzledClasses() {
    static NSMutableSet *set;
    static dispatch_once_t pred;
    
    dispatch_once(&pred, ^{
        set = [[NSMutableSet alloc] init];
    });

    return set;
}

@implementation NSInvocation (YZTypeParsing)

- (id)yz_argumentAtIndex:(NSUInteger)index {
#define WRAP_AND_RETURN(type) \
    do { \
        type val = 0; \
        [self getArgument:&val atIndex:(NSInteger)index]; \
        return @(val); \
    } while (0)

    const char *argType = [self.methodSignature getArgumentTypeAtIndex:index];
    // Skip const type qualifier.
    if (argType[0] == 'r') {
        argType++;
    }

    if (strcmp(argType, @encode(id)) == 0 || strcmp(argType, @encode(Class)) == 0) {
        __autoreleasing id returnObj;
        [self getArgument:&returnObj atIndex:(NSInteger)index];
        return returnObj;
    } else if (strcmp(argType, @encode(char)) == 0) {
        WRAP_AND_RETURN(char);
    } else if (strcmp(argType, @encode(int)) == 0) {
        WRAP_AND_RETURN(int);
    } else if (strcmp(argType, @encode(short)) == 0) {
        WRAP_AND_RETURN(short);
    } else if (strcmp(argType, @encode(long)) == 0) {
        WRAP_AND_RETURN(long);
    } else if (strcmp(argType, @encode(long long)) == 0) {
        WRAP_AND_RETURN(long long);
    } else if (strcmp(argType, @encode(unsigned char)) == 0) {
        WRAP_AND_RETURN(unsigned char);
    } else if (strcmp(argType, @encode(unsigned int)) == 0) {
        WRAP_AND_RETURN(unsigned int);
    } else if (strcmp(argType, @encode(unsigned short)) == 0) {
        WRAP_AND_RETURN(unsigned short);
    } else if (strcmp(argType, @encode(unsigned long)) == 0) {
        WRAP_AND_RETURN(unsigned long);
    } else if (strcmp(argType, @encode(unsigned long long)) == 0) {
        WRAP_AND_RETURN(unsigned long long);
    } else if (strcmp(argType, @encode(float)) == 0) {
        WRAP_AND_RETURN(float);
    } else if (strcmp(argType, @encode(double)) == 0) {
        WRAP_AND_RETURN(double);
    } else if (strcmp(argType, @encode(BOOL)) == 0) {
        WRAP_AND_RETURN(BOOL);
    } else if (strcmp(argType, @encode(char *)) == 0) {
        WRAP_AND_RETURN(const char *);
    } else if (strcmp(argType, @encode(void (^)(void))) == 0) {
        __unsafe_unretained id block = nil;
        [self getArgument:&block atIndex:(NSInteger)index];
        return [block copy];
    } else {
        NSUInteger valueSize = 0;
        NSGetSizeAndAlignment(argType, &valueSize, NULL);

        unsigned char valueBytes[valueSize];
        [self getArgument:valueBytes atIndex:(NSInteger)index];
        
        return [NSValue valueWithBytes:valueBytes objCType:argType];
    }

    return nil;

#undef WRAP_AND_RETURN
}

- (NSArray *)yz_argumentsArray {
    NSUInteger numberOfArguments = self.methodSignature.numberOfArguments;
    NSMutableArray *argumentsArray = [NSMutableArray arrayWithCapacity:numberOfArguments - 2];
    for (NSUInteger index = 2; index < numberOfArguments; index++) {
        [argumentsArray addObject:[self yz_argumentAtIndex:index] ?: [NSNull null]];
    }

    return argumentsArray.copy;
}

@end


@implementation NSObject (YZHookHandler)

+ (NSString *)yz_hookHandlerForSelectorAliasPrefix{
    return _yz_hookHandlerForSelectorAliasPrefix;
}

+ (void)setYz_hookHandlerForSelectorAliasPrefix:(NSString *)aliasPrefix{
    _yz_hookHandlerForSelectorAliasPrefix = aliasPrefix;
}

+ (NSString *)yz_subclassSuffix{
    return _yz_subclassSuffix;
}

+ (void)setYz_subclassSuffix:(NSString *)subclassSuffix{
    _yz_subclassSuffix = subclassSuffix;
}


static BOOL YZForwardInvocation(id self, NSInvocation *invocation) {
    SEL aliasSelector = YZAliasForSelector(invocation.selector);
    NSMutableArray *handlers = objc_getAssociatedObject(self, aliasSelector);

    Class class = object_getClass(invocation.target);
    BOOL respondsToAlias = [class instancesRespondToSelector:aliasSelector];
    if (respondsToAlias) {
        invocation.selector = aliasSelector;
        NSArray *args = invocation.yz_argumentsArray;
        for (YZHookHandler *handler in handlers) {
            !handler.befor ? : handler.befor(args);
            if (handler.instead) {
                 handler.instead(args);
            }else{
                [invocation invoke];
            }
            !handler.after ? : handler.after(args);
        }
    }

    if (handlers == nil) return respondsToAlias;
    
    return YES;
}

static void YZSwizzleForwardInvocation(Class class) {
    SEL forwardInvocationSEL = @selector(forwardInvocation:);
    Method forwardInvocationMethod = class_getInstanceMethod(class, forwardInvocationSEL);

    // Preserve any existing implementation of -forwardInvocation:.
    void (*originalForwardInvocation)(id, SEL, NSInvocation *) = NULL;
    if (forwardInvocationMethod != NULL) {
        originalForwardInvocation = (__typeof__(originalForwardInvocation))method_getImplementation(forwardInvocationMethod);
    }

    // Set up a new version of -forwardInvocation:.
    //
    // If the selector has been passed to -yz_hookForSelector:, invoke
    // the aliased method, and forward the arguments to any attached signals.
    //
    // If the selector has not been passed to -yz_hookForSelector:,
    // invoke any existing implementation of -forwardInvocation:. If there
    // was no existing implementation, throw an unrecognized selector
    // exception.
    id newForwardInvocation = ^(id self, NSInvocation *invocation) {
        BOOL matched = YZForwardInvocation(self, invocation);
        if (matched) return;

        if (originalForwardInvocation == NULL) {
            [self doesNotRecognizeSelector:invocation.selector];
        } else {
            originalForwardInvocation(self, forwardInvocationSEL, invocation);
        }
    };

    class_replaceMethod(class, forwardInvocationSEL, imp_implementationWithBlock(newForwardInvocation), "v@:@");
}

Method yz_getImmediateInstanceMethod (Class aClass, SEL aSelector) {
    unsigned methodCount = 0;
    Method *methods = class_copyMethodList(aClass, &methodCount);
    Method foundMethod = NULL;

    for (unsigned methodIndex = 0;methodIndex < methodCount;++methodIndex) {
        if (method_getName(methods[methodIndex]) == aSelector) {
            foundMethod = methods[methodIndex];
            break;
        }
    }

    free(methods);
    return foundMethod;
}

static void YZSwizzleRespondsToSelector(Class class) {
    SEL respondsToSelectorSEL = @selector(respondsToSelector:);

    // Preserve existing implementation of -respondsToSelector:.
    Method respondsToSelectorMethod = class_getInstanceMethod(class, respondsToSelectorSEL);
    BOOL (*originalRespondsToSelector)(id, SEL, SEL) = (__typeof__(originalRespondsToSelector))method_getImplementation(respondsToSelectorMethod);

    // Set up a new version of -respondsToSelector: that returns YES for methods
    // added by -yz_hookForSelector:.
    //
    // If the selector has a method defined on the receiver's actual class, and
    // if that method's implementation is _objc_msgForward, then returns whether
    // the instance has a signal for the selector.
    // Otherwise, call the original -respondsToSelector:.
    id newRespondsToSelector = ^ BOOL (id self, SEL selector) {
        Method method = yz_getImmediateInstanceMethod(class, selector);

        if (method != NULL && method_getImplementation(method) == _objc_msgForward) {
            SEL aliasSelector = YZAliasForSelector(selector);
            if (objc_getAssociatedObject(self, aliasSelector) != nil) return YES;
        }

        return originalRespondsToSelector(self, respondsToSelectorSEL, selector);
    };

    class_replaceMethod(class, respondsToSelectorSEL, imp_implementationWithBlock(newRespondsToSelector), method_getTypeEncoding(respondsToSelectorMethod));
}


static void YZSwizzleGetClass(Class class, Class statedClass) {
    SEL selector = @selector(class);
    Method method = class_getInstanceMethod(class, selector);
    IMP newIMP = imp_implementationWithBlock(^(id self) {
        return statedClass;
    });
    class_replaceMethod(class, selector, newIMP, method_getTypeEncoding(method));
}

static void YZSwizzleMethodSignatureForSelector(Class class) {
    IMP newIMP = imp_implementationWithBlock(^(id self, SEL selector) {
        // Don't send the -class message to the receiver because we've changed
        // that to return the original class.
        Class actualClass = object_getClass(self);
        Method method = class_getInstanceMethod(actualClass, selector);
        if (method == NULL) {
            // Messages that the original class dynamically implements fall
            // here.
            //
            // Call the original class' -methodSignatureForSelector:.
            struct objc_super target = {
                .super_class = class_getSuperclass(class),
                .receiver = self,
            };
            NSMethodSignature * (*messageSend)(struct objc_super *, SEL, SEL) = (__typeof__(messageSend))objc_msgSendSuper;
            return messageSend(&target, @selector(methodSignatureForSelector:), selector);
        }

        char const *encoding = method_getTypeEncoding(method);
        return [NSMethodSignature signatureWithObjCTypes:encoding];
    });

    SEL selector = @selector(methodSignatureForSelector:);
    Method methodSignatureForSelectorMethod = class_getInstanceMethod(class, selector);
    class_replaceMethod(class, selector, newIMP, method_getTypeEncoding(methodSignatureForSelectorMethod));
}


static Class YZSwizzleClass(NSObject *self) {
    Class statedClass = self.class;
    Class baseClass = object_getClass(self);

    // The "known dynamic subclass" is the subclass generated by handler.
    // It's stored as an associated object on every instance that's already
    // been swizzled, so that even if something else swizzles the class of
    // this instance, we can still access the handler generated subclass.
    Class knownDynamicSubclass = objc_getAssociatedObject(self, YZSubclassAssociationKey);
    if (knownDynamicSubclass != Nil) return knownDynamicSubclass;

    NSString *className = NSStringFromClass(baseClass);

    if (statedClass != baseClass) {
        // If the class is already lying about what it is, it's probably a KVO
        // dynamic subclass or something else that we shouldn't subclass
        // ourselves.
        //
        // Just swizzle -forwardInvocation: in-place. Since the object's class
        // was almost certainly dynamically changed, we shouldn't see another of
        // these classes in the hierarchy.
        //
        // Additionally, swizzle -respondsToSelector: because the default
        // implementation may be ignorant of methods added to this class.
        @synchronized (swizzledClasses()) {
            if (![swizzledClasses() containsObject:className]) {
                YZSwizzleForwardInvocation(baseClass);
                YZSwizzleRespondsToSelector(baseClass);
                YZSwizzleGetClass(baseClass, statedClass);
                YZSwizzleGetClass(object_getClass(baseClass), statedClass);
                YZSwizzleMethodSignatureForSelector(baseClass);
                [swizzledClasses() addObject:className];
            }
        }

        return baseClass;
    }

    const char *subclassName = [className stringByAppendingString:_yz_subclassSuffix].UTF8String;
    Class subclass = objc_getClass(subclassName);

    if (subclass == nil) {
        subclass = objc_allocateClassPair(baseClass, subclassName, 0);
        if (subclass == nil) return nil;

        YZSwizzleForwardInvocation(subclass);
        YZSwizzleRespondsToSelector(subclass);

        YZSwizzleGetClass(subclass, statedClass);
        YZSwizzleGetClass(object_getClass(subclass), statedClass);

        YZSwizzleMethodSignatureForSelector(subclass);

        objc_registerClassPair(subclass);
    }

    object_setClass(self, subclass);
    objc_setAssociatedObject(self, YZSubclassAssociationKey, subclass, OBJC_ASSOCIATION_ASSIGN);
    return subclass;
}

static SEL YZAliasForSelector(SEL originalSelector) {
    NSString *selectorName = NSStringFromSelector(originalSelector);
    return NSSelectorFromString([_yz_hookHandlerForSelectorAliasPrefix stringByAppendingString:selectorName]);
}

static const char *YZSignatureForUndefinedSelector(SEL selector) {
    const char *name = sel_getName(selector);
    NSMutableString *signature = [NSMutableString stringWithString:@"v@:"];

    while ((name = strchr(name, ':')) != NULL) {
        [signature appendString:@"@"];
        name++;
    }

    return signature.UTF8String;
}

static void YZCheckTypeEncoding(const char *typeEncoding) {
#if !NS_BLOCK_ASSERTIONS
    // Some types, including vector types, are not encoded. In these cases the
    // signature starts with the size of the argument frame.
    NSCAssert(*typeEncoding < '1' || *typeEncoding > '9', @"unknown method return type not supported in type encoding: %s", typeEncoding);
    NSCAssert(strstr(typeEncoding, "(") != typeEncoding, @"union method return type not supported");
    NSCAssert(strstr(typeEncoding, "{") != typeEncoding, @"struct method return type not supported");
    NSCAssert(strstr(typeEncoding, "[") != typeEncoding, @"array method return type not supported");
    NSCAssert(strstr(typeEncoding, @encode(_Complex float)) != typeEncoding, @"complex float method return type not supported");
    NSCAssert(strstr(typeEncoding, @encode(_Complex double)) != typeEncoding, @"complex double method return type not supported");
    NSCAssert(strstr(typeEncoding, @encode(_Complex long double)) != typeEncoding, @"complex long double method return type not supported");

#endif // !NS_BLOCK_ASSERTIONS
}

static YZHookHandler *NSObjectForSelector(NSObject *self, SEL selector, Protocol *protocol) {
    SEL aliasSelector = YZAliasForSelector(selector);
    
    @synchronized (self) {
        NSMutableArray *allSelectors = objc_getAssociatedObject(self, YZAllSelectorsAssociationKey);
        if (!allSelectors){
            allSelectors = @[].mutableCopy;
            objc_setAssociatedObject(self, YZAllSelectorsAssociationKey, allSelectors, OBJC_ASSOCIATION_RETAIN);
        }
        
        NSMutableArray *handlers = objc_getAssociatedObject(self, aliasSelector);
        if (handlers == nil) {
            handlers = @[].mutableCopy;
            objc_setAssociatedObject(self, aliasSelector, handlers, OBJC_ASSOCIATION_RETAIN);
            [allSelectors addObject:handlers];
        }
        YZHookHandler *handler = [[YZHookHandler alloc] initWithHookTarget:self forSelector:selector fromProtocol:protocol];
        handler.handlers = handlers;
        [handlers addObject:handler];
        
        Class class = YZSwizzleClass(self);
        NSCAssert(class != nil, @"Could not swizzle class of %@", self);

        Method targetMethod = class_getInstanceMethod(class, selector);
        if (targetMethod == NULL) {
            const char *typeEncoding;
            if (protocol == NULL) {
                typeEncoding = YZSignatureForUndefinedSelector(selector);
            } else {
                // Look for the selector as an optional instance method.
                struct objc_method_description methodDescription = protocol_getMethodDescription(protocol, selector, NO, YES);

                if (methodDescription.name == NULL) {
                    // Then fall back to looking for a required instance
                    // method.
                    methodDescription = protocol_getMethodDescription(protocol, selector, YES, YES);
                    NSCAssert(methodDescription.name != NULL, @"Selector %@ does not exist in <%s>", NSStringFromSelector(selector), protocol_getName(protocol));
                }

                typeEncoding = methodDescription.types;
            }

            YZCheckTypeEncoding(typeEncoding);

            // Define the selector to call -forwardInvocation:.
            if (!class_addMethod(class, selector, _objc_msgForward, typeEncoding)) {
                NSDictionary *userInfo = @{
                    NSLocalizedDescriptionKey: [NSString stringWithFormat:NSLocalizedString(@"A race condition occurred implementing %@ on class %@", nil), NSStringFromSelector(selector), class],
                    NSLocalizedRecoverySuggestionErrorKey: NSLocalizedString(@"Invoke -yz_hookForSelector: again to override the implementation.", nil)
                };
                [handlers removeObject:handler];
                return [[YZHookHandler alloc] initWithError:[NSError errorWithDomain:YZHookHandlerErrorDomain code:YZHookHandlerSelectorErrorMethodSwizzlingRace userInfo:userInfo]];
            }
        } else if (method_getImplementation(targetMethod) != _objc_msgForward) {
            // Make a method alias for the existing method implementation.
            const char *typeEncoding = method_getTypeEncoding(targetMethod);

            YZCheckTypeEncoding(typeEncoding);

            BOOL addedAlias __attribute__((unused)) = class_addMethod(class, aliasSelector, method_getImplementation(targetMethod), typeEncoding);
            NSCAssert(addedAlias, @"Original implementation for %@ is already copied to %@ on %@", NSStringFromSelector(selector), NSStringFromSelector(aliasSelector), class);

            // Redefine the selector to call -forwardInvocation:.
            class_replaceMethod(class, selector, _objc_msgForward, method_getTypeEncoding(targetMethod));
        }
        return handler;
    }
}

- (YZHookHandler *)yz_hookForSelector:(SEL)selector {
    NSCParameterAssert(selector != NULL);
    
    return NSObjectForSelector(self, selector, NULL);

}

- (YZHookHandler *)yz_hookForSelector:(SEL)selector fromProtocol:(Protocol *)protocol{
    NSCParameterAssert(selector != NULL);
    NSCParameterAssert(protocol != NULL);
    
    return NSObjectForSelector(self, selector, protocol);
}

- (void)yz_cancelHook{
    
    Class knownDynamicSubclass = objc_getAssociatedObject(self, YZSubclassAssociationKey);
    if (knownDynamicSubclass == Nil) return;
    
    objc_setAssociatedObject(self, YZSubclassAssociationKey, nil, OBJC_ASSOCIATION_ASSIGN);
    
    NSString *knownDynamicSubclassName = NSStringFromClass(knownDynamicSubclass);
    
    NSString *className = [knownDynamicSubclassName stringByReplacingOccurrencesOfString:_yz_subclassSuffix withString:@""];
    
    @synchronized (swizzledClasses()) {
        if ([swizzledClasses() containsObject:className]) {
            [swizzledClasses() removeObject:className];
        }
    }
    Class class = objc_getClass(className.UTF8String);
    object_setClass(self, class);
}

- (void)yz_removeAllHooks{
    NSMutableArray *allSelectors = objc_getAssociatedObject(self, YZAllSelectorsAssociationKey);
    NSMutableArray *tmp = allSelectors.copy;
    for (NSMutableArray *handles in tmp) {
        [handles removeAllObjects];
    }
    [allSelectors removeAllObjects];
    [self yz_cancelHook];
}

@end

@implementation YZHookHandler
#define YZHookLogError(...) do { NSLog(__VA_ARGS__); }while(0)

- (instancetype)initWithHookTarget:(id)target forSelector:(SEL)selector fromProtocol:(Protocol *)protocol{
    self = [super init];
    if (self) {
        _target = target;
        _selector = selector;
        _protocol = protocol;
    }
    return self;
}

- (instancetype)initWithError:(NSError *)error{
    self = [super init];
    if (self) {
        _error = error;
        YZHookLogError(@"%@",error);
    }
    return self;
}

- (instancetype)initWithHookTarget:(id)target forSelector:(SEL)selector{
    return [self initWithHookTarget:target forSelector:selector fromProtocol:nil];
}

- (YZHookHandler *)after:(YZHookArgsBlock)after{
    if (_error) return self;
    _after = [after copy];
    return self;
}

- (YZHookHandler *)instead:(YZHookArgsBlock)instead {
    if (_error) return self;
    _instead = [instead copy];
    return self;
}

- (YZHookHandler *)befor:(YZHookArgsBlock)befor {
    if (_error) return self;
    _befor = [befor copy];
    return self;
}

- (void)removeHook{
    [self.handlers removeObject:self];
    if (!self.handlers.count) {
        NSMutableArray *allSelectors = objc_getAssociatedObject(self.target, YZAllSelectorsAssociationKey);
        [allSelectors removeObject:self.handlers];
        if (!allSelectors.count)  [self.target yz_cancelHook];
    }
}

@end
