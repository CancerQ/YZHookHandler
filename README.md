
YZHookHandler
==============

YZHookHandler uses Objective-C message forwarding to hook into messages. This will create some overhead. Don't add hook to methods that are called a lot. YZHookHandler is meant for view/controller code that is not called a 1000 times per second.
Adding hook returns a handler which can be used to deregister again. All calls are thread safe.

Most of the code is referenced from `ReactiveObjC`.

Demo Project
==============
See `Demo/Demo.xcodeproj`

Installation
==============

### CocoaPods

1. Add `pod 'YZHookHandler'` to your Podfile.
2. Run `pod install` or `pod update`.
3. Import \<YZHookHandler/YZHookHandler.h\>.

### Manually

1. Download all the files in the `YZHookHandler` subdirectory.
2. Add the source files to your Xcode project.

Requirements
==============
This library requires `iOS 8.0+` and `Xcode 9.0`.

Usage
==============
YZHookHandler extends `NSObject` with the following methods:

```obj-c

    [[viewController yz_hookForSelector:@selector(viewWillAppear:)] after:^(NSArray * _Nonnull args) {
        BOOL animated = args[0];
        NSLog(@"viewWillAppear: %d", animated);
    }];
```

License
==============
YZHookHandler is provided under the MIT license. See LICENSE file for details.
