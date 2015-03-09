//
//  WFNotificationCenterTests.m
//  WFNotificationCenter
//
//  Created by Conrad Kramer on 3/8/15.
//  Copyright (c) 2015 DeskConnect, Inc. All rights reserved.
//

#import <XCTest/XCTest.h>

#import "WFDistributedNotificationCenter.h"
#import "fishhook.h"

#include <dlfcn.h>

@interface WFNotificationCenterTests : XCTestCase

@property (nonatomic, strong) WFDistributedNotificationCenter *center;

@property (nonatomic, strong) NSNotification *lastNotification;

@end

static pid_t custom_pid = -1;
static pid_t (*orig_getpid)();

static NSString * WFNotificationCenterTestAppGroup = @"com.deskconnect.test";
static NSString * const WFTestNotificationName = @"Test";
static NSString * const WFSecondTestNotificationName = @"Test2";

static pid_t custom_getpid() {
    if (custom_pid > 0)
        return custom_pid;
    return orig_getpid();
}

static void set_pid(pid_t pid) {
    custom_pid = pid;
}

@implementation WFNotificationCenterTests

+ (void)load {
    orig_getpid = dlsym(RTLD_DEFAULT, "getpid");
    rebind_symbols((struct rebinding[1]){"getpid", custom_getpid}, 1);
}

- (void)setUp {
    [super setUp];
    self.center = [[WFDistributedNotificationCenter alloc] initWithSecurityApplicationGroupIdentifier:WFNotificationCenterTestAppGroup];
}

- (void)tearDown {
    self.center = nil;
    self.lastNotification = nil;
    [super tearDown];
}

- (void)receive:(NSNotification *)notification {
    self.lastNotification = notification;
}

#pragma mark - Observers

- (void)testAddingObserver {
    [self.center addObserver:self selector:@selector(receive:) name:WFTestNotificationName];
    
    [self keyValueObservingExpectationForObject:self keyPath:NSStringFromSelector(@selector(lastNotification)) expectedValue:nil];
    [self.center postNotificationName:WFTestNotificationName];
    [self waitForExpectationsWithTimeout:1.0f handler:nil];
    XCTAssert([self.lastNotification.name isEqualToString:WFTestNotificationName]);
}

- (void)testRemovingObserver {
    [self.center addObserver:self selector:@selector(receive:) name:WFTestNotificationName];
    [self.center addObserver:self selector:@selector(receive:) name:WFSecondTestNotificationName];
    [self.center removeObserver:self];
    
    [self.center postNotificationName:WFTestNotificationName];
    [self.center postNotificationName:WFSecondTestNotificationName];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.0f]];
    XCTAssertNil(self.lastNotification);
}

- (void)testRemovingNamedObserver {
    [self.center addObserver:self selector:@selector(receive:) name:WFTestNotificationName];
    [self.center addObserver:self selector:@selector(receive:) name:WFSecondTestNotificationName];
    [self.center removeObserver:self name:WFTestNotificationName];
    
    [self.center postNotificationName:WFTestNotificationName];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.0f]];
    XCTAssertNil(self.lastNotification);
    
    [self keyValueObservingExpectationForObject:self keyPath:NSStringFromSelector(@selector(lastNotification)) expectedValue:nil];
    [self.center postNotificationName:WFSecondTestNotificationName];
    [self waitForExpectationsWithTimeout:1.0f handler:nil];
    XCTAssert([self.lastNotification.name isEqualToString:WFSecondTestNotificationName]);
}

@end
