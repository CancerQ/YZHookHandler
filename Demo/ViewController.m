//
//  ViewController.m
//  Demo
//
//  Created by zhiqiang_ye on 2020/11/7.
//  Copyright © 2020 CancerQ. All rights reserved.
//

#import "ViewController.h"
#import "YZHookHandler.h"

@interface ViewController ()

@end

@interface YZTest : NSObject
- (void)test;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    YZTest *test1 = [YZTest new];
    
    __weak YZTest *weakTest1 = test1;
    [[[weakTest1 yz_hookForSelector:@selector(test)] after:^(NSArray * _Nonnull args) {
        NSLog(@"after %@",weakTest1);
    }] befor:^(NSArray * _Nonnull args) {
        NSLog(@"befor %@",weakTest1);
    }] ;
    
    [test1 test];
    
    
    NSObject.yz_subclassSuffix = @"_test";
    NSObject.yz_hookHandlerForSelectorAliasPrefix = @"test_";
    
    YZTest *test2 = [YZTest new];
    
    [[test2 yz_hookForSelector:@selector(test)] after:^(NSArray * _Nonnull args) {

    }];
    
    [test2 test];
    
}

@end


@implementation YZTest

- (void)test{
    NSLog(@"%@",NSStringFromSelector(_cmd));
}

- (void)dealloc{
    NSLog(@"%s dealloc", object_getClassName(self));
}

@end
