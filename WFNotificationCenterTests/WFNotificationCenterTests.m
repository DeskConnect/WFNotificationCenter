//
//  WFNotificationCenterTests.m
//  WFNotificationCenter
//
//  Created by Conrad Kramer on 3/8/15.
//  Copyright (c) 2015 DeskConnect, Inc. All rights reserved.
//

#import <XCTest/XCTest.h>
#include <dlfcn.h>

#import "WFDistributedNotificationCenter.h"
#import "fishhook.h"

#define WFAssertEqualNotifications(notification1, notification2, ...) \
    XCTAssertEqualObjects([(NSNotification *)notification1 name], [(NSNotification *)notification2 name], __VA_ARGS__); \
    XCTAssertEqualObjects([(NSNotification *)notification1 object], [(NSNotification *)notification2 object], __VA_ARGS__); \
    XCTAssertEqualObjects([(NSNotification *)notification1 userInfo], [(NSNotification *)notification2 userInfo] __VA_ARGS__,);

@interface WFNotificationCenterTests : XCTestCase

@property (nonatomic, strong) WFDistributedNotificationCenter *center;
@property (nonatomic, strong) NSMutableArray *notifications;
@property (nonatomic, readonly) NSNotification *lastNotification;

@end

static pid_t custom_pid = -1;
static pid_t (*orig_getpid)();

static pid_t custom_getpid() {
    if (custom_pid > 0)
        return custom_pid;
    return orig_getpid();
}

static void set_pid(pid_t pid) {
    custom_pid = pid;
}

static void reset_pid() {
    custom_pid = -1;
}

static NSString * const WFNotificationCenterTestAppGroup = @"com.deskconnect.test";
static NSString * const WFTestNotificationName = @"Test";
static NSString * const WFSecondTestNotificationName = @"Test2";
static NSString * const WFTestObject = @"Object";
static NSString * const WFSecondTestObject = @"Object2";

@implementation WFNotificationCenterTests

+ (void)load {
    orig_getpid = dlsym(RTLD_DEFAULT, "getpid");
    rebind_symbols((struct rebinding[1]){"getpid", custom_getpid}, 1);
}

- (void)setUp {
    [super setUp];
    [self willChangeValueForKey:NSStringFromSelector(@selector(lastNotification))];
    self.notifications = [NSMutableArray new];
    [self didChangeValueForKey:NSStringFromSelector(@selector(lastNotification))];
    self.center = [[WFDistributedNotificationCenter alloc] initWithSecurityApplicationGroupIdentifier:WFNotificationCenterTestAppGroup];
}

- (void)tearDown {
    self.center = nil;
    self.notifications = nil;
    [super tearDown];
}

- (void)receive:(NSNotification *)notification {
    [self willChangeValueForKey:NSStringFromSelector(@selector(lastNotification))];
    [self.notifications addObject:notification];
    [self didChangeValueForKey:NSStringFromSelector(@selector(lastNotification))];
}

- (NSNotification *)lastNotification {
    return self.notifications.lastObject;
}

#pragma mark - Serialization

- (void)testNonStringObject {
    NSNotification *notification = [NSNotification notificationWithName:WFTestNotificationName object:@YES];
    XCTAssertThrowsSpecificNamed([self.center postNotification:notification], NSException, NSInternalInconsistencyException);
}

- (void)testSecureCoding {
    [self.center addObserver:self selector:@selector(receive:) name:nil object:nil];
    NSNotification *notification = [NSNotification notificationWithName:WFTestNotificationName object:@"Foo" userInfo:@{@"Bar": @YES, @"Baz": @[@1,@2,@3]}];
    
    [self keyValueObservingExpectationForObject:self keyPath:NSStringFromSelector(@selector(lastNotification)) expectedValue:nil];
    [self.center postNotification:notification];
    [self waitForExpectationsWithTimeout:0.5f handler:nil];
    WFAssertEqualNotifications(self.lastNotification, notification);
}

#pragma mark - Observers

- (void)testAddingObserver {
    [self.center addObserver:self selector:@selector(receive:) name:nil object:nil];
    
    [self keyValueObservingExpectationForObject:self keyPath:NSStringFromSelector(@selector(lastNotification)) expectedValue:nil];
    [self.center postNotificationName:WFTestNotificationName object:nil];
    [self waitForExpectationsWithTimeout:0.5f handler:nil];
    XCTAssertEqualObjects(self.lastNotification.name, WFTestNotificationName);
    
    [self keyValueObservingExpectationForObject:self keyPath:NSStringFromSelector(@selector(lastNotification)) expectedValue:nil];
    [self.center postNotificationName:WFSecondTestNotificationName object:nil];
    [self waitForExpectationsWithTimeout:0.5f handler:nil];
    XCTAssertEqualObjects(self.lastNotification.name, WFSecondTestNotificationName);
}

- (void)testAddingNamedObserver {
    [self.center addObserver:self selector:@selector(receive:) name:WFTestNotificationName object:nil];
    
    [self.center postNotificationName:WFSecondTestNotificationName object:nil];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5f]];
    XCTAssertNil(self.lastNotification);
    
    [self keyValueObservingExpectationForObject:self keyPath:NSStringFromSelector(@selector(lastNotification)) expectedValue:nil];
    [self.center postNotificationName:WFTestNotificationName object:nil];
    [self waitForExpectationsWithTimeout:0.5f handler:nil];
    XCTAssertEqualObjects(self.lastNotification.name, WFTestNotificationName);
}

- (void)testAddingObserverWithObject {
    [self.center addObserver:self selector:@selector(receive:) name:nil object:WFTestObject];
    
    [self.center postNotificationName:WFTestNotificationName object:WFSecondTestObject];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5f]];
    XCTAssertNil(self.lastNotification);
    
    [self keyValueObservingExpectationForObject:self keyPath:NSStringFromSelector(@selector(lastNotification)) expectedValue:nil];
    [self.center postNotificationName:WFTestNotificationName object:WFTestObject];
    [self waitForExpectationsWithTimeout:0.5f handler:nil];
    XCTAssertEqualObjects(self.lastNotification.name, WFTestNotificationName);
    XCTAssertEqualObjects(self.lastNotification.object, WFTestObject);
    
    [self keyValueObservingExpectationForObject:self keyPath:NSStringFromSelector(@selector(lastNotification)) expectedValue:nil];
    [self.center postNotificationName:WFSecondTestNotificationName object:WFTestObject];
    [self waitForExpectationsWithTimeout:0.5f handler:nil];
    XCTAssertEqualObjects(self.lastNotification.name, WFSecondTestNotificationName);
    XCTAssertEqualObjects(self.lastNotification.object, WFTestObject);
}

- (void)testAddingNamedObserverWithObject {
    [self.center addObserver:self selector:@selector(receive:) name:WFTestNotificationName object:WFTestObject];
    
    [self.center postNotificationName:WFTestNotificationName object:WFSecondTestObject];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5f]];
    XCTAssertNil(self.lastNotification);
    
    [self.center postNotificationName:WFSecondTestObject object:WFTestObject];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5f]];
    XCTAssertNil(self.lastNotification);
    
    [self keyValueObservingExpectationForObject:self keyPath:NSStringFromSelector(@selector(lastNotification)) expectedValue:nil];
    [self.center postNotificationName:WFTestNotificationName object:WFTestObject];
    [self waitForExpectationsWithTimeout:0.5f handler:nil];
    XCTAssertEqualObjects(self.lastNotification.name, WFTestNotificationName);
    XCTAssertEqualObjects(self.lastNotification.object, WFTestObject);
}

- (void)testAddingBlockObserver {
    __weak __typeof__(self) weakSelf = self;
    XCTestExpectation *expectation = [self expectationWithDescription:nil];
    [self.center addObserverForName:WFTestNotificationName object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        [weakSelf.notifications addObject:note];
        [expectation fulfill];
    }];
    [self.center postNotificationName:WFTestNotificationName object:nil];
    [self waitForExpectationsWithTimeout:0.5f handler:nil];
    XCTAssertEqualObjects(self.lastNotification.name, WFTestNotificationName);
}

- (void)testRemovingObserver {
    [self.center addObserver:self selector:@selector(receive:) name:WFTestNotificationName object:nil];
    [self.center addObserver:self selector:@selector(receive:) name:WFSecondTestNotificationName object:nil];
    [self.center removeObserver:self];
    
    [self.center postNotificationName:WFTestNotificationName object:nil];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5f]];
    XCTAssertNil(self.lastNotification);
    
    [self.center postNotificationName:WFSecondTestNotificationName object:nil];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5f]];
    XCTAssertNil(self.lastNotification);
}

- (void)testRemovingNamedObserver {
    [self.center addObserver:self selector:@selector(receive:) name:WFTestNotificationName object:nil];
    [self.center addObserver:self selector:@selector(receive:) name:WFSecondTestNotificationName object:nil];
    [self.center removeObserver:self name:WFTestNotificationName object:nil];
    
    [self.center postNotificationName:WFTestNotificationName object:nil];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5f]];
    XCTAssertNil(self.lastNotification);
    
    [self keyValueObservingExpectationForObject:self keyPath:NSStringFromSelector(@selector(lastNotification)) expectedValue:nil];
    [self.center postNotificationName:WFSecondTestNotificationName object:nil];
    [self waitForExpectationsWithTimeout:0.5f handler:nil];
    XCTAssertEqualObjects(self.lastNotification.name, WFSecondTestNotificationName);
}

- (void)testRemovingObserverWithObject {
    [self.center addObserver:self selector:@selector(receive:) name:WFTestNotificationName object:WFTestObject];
    [self.center addObserver:self selector:@selector(receive:) name:WFTestNotificationName object:WFSecondTestObject];
    [self.center removeObserver:self name:WFTestNotificationName object:WFTestObject];
    
    [self.center postNotificationName:WFTestNotificationName object:WFTestObject];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5f]];
    XCTAssertNil(self.lastNotification);
    
    [self keyValueObservingExpectationForObject:self keyPath:NSStringFromSelector(@selector(lastNotification)) expectedValue:nil];
    [self.center postNotificationName:WFTestNotificationName object:WFSecondTestObject];
    [self waitForExpectationsWithTimeout:0.5f handler:nil];
    XCTAssertEqualObjects(self.lastNotification.object, WFSecondTestObject);
}

- (void)testRemovingNamedObserverWithObject {
    [self.center addObserver:self selector:@selector(receive:) name:WFTestNotificationName object:WFTestObject];
    [self.center addObserver:self selector:@selector(receive:) name:WFSecondTestNotificationName object:WFSecondTestObject];
    [self.center removeObserver:self name:WFTestNotificationName object:WFSecondTestObject];
    [self.center removeObserver:self name:WFSecondTestNotificationName object:WFTestObject];
    
    [self keyValueObservingExpectationForObject:self keyPath:NSStringFromSelector(@selector(lastNotification)) expectedValue:nil];
    [self.center postNotificationName:WFTestNotificationName object:WFTestObject];
    [self waitForExpectationsWithTimeout:0.5f handler:nil];
    XCTAssertEqualObjects(self.lastNotification.name, WFTestNotificationName);
    XCTAssertEqualObjects(self.lastNotification.object, WFTestObject);
    
    [self keyValueObservingExpectationForObject:self keyPath:NSStringFromSelector(@selector(lastNotification)) expectedValue:nil];
    [self.center postNotificationName:WFSecondTestNotificationName object:WFSecondTestObject];
    [self waitForExpectationsWithTimeout:0.5f handler:nil];
    XCTAssertEqualObjects(self.lastNotification.name, WFSecondTestNotificationName);
    XCTAssertEqualObjects(self.lastNotification.object, WFSecondTestObject);
}

- (void)testRemovingBlockObserver {
    __weak __typeof__(self) weakSelf = self;
    __weak id observer = [self.center addObserverForName:WFTestNotificationName object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        [weakSelf.notifications addObject:note];
    }];
    XCTAssertNotNil(observer);
    
    [self.center removeObserver:observer];
    [self.center postNotificationName:WFTestNotificationName object:nil];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5f]];
    XCTAssertNil(self.lastNotification);
}

#pragma mark - Multiple Centers

- (void)testMultipleCentersInSameProcess {
    WFDistributedNotificationCenter *otherCenter = [[WFDistributedNotificationCenter alloc] initWithSecurityApplicationGroupIdentifier:WFNotificationCenterTestAppGroup];
    WFDistributedNotificationCenter *yetAnotherCenter = [[WFDistributedNotificationCenter alloc] initWithSecurityApplicationGroupIdentifier:WFNotificationCenterTestAppGroup];
    [self testCommunicationBetweenCenters:@[self.center, otherCenter, yetAnotherCenter]];
}

- (void)testMultipleCentersInDifferentProcesses {
    set_pid(getpid() / 2);
    WFDistributedNotificationCenter *otherCenter = [[WFDistributedNotificationCenter alloc] initWithSecurityApplicationGroupIdentifier:WFNotificationCenterTestAppGroup];
    set_pid(getpid() / 2);
    WFDistributedNotificationCenter *yetAnotherCenter = [[WFDistributedNotificationCenter alloc] initWithSecurityApplicationGroupIdentifier:WFNotificationCenterTestAppGroup];
    reset_pid();
    [self testCommunicationBetweenCenters:@[self.center, otherCenter, yetAnotherCenter]];
}

- (void)testCommunicationBetweenCenters:(NSArray *)centers {
    for (WFDistributedNotificationCenter *center in centers) {
        [center addObserver:self selector:@selector(receive:) name:WFTestNotificationName object:nil];
    }
    
    for (WFDistributedNotificationCenter *center in centers) {
        [self.notifications removeAllObjects];
        [center postNotificationName:WFTestNotificationName object:nil];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.0f]];
        
        XCTAssertTrue(self.notifications.count == centers.count);
        XCTAssertEqualObjects(self.lastNotification.name, WFTestNotificationName);
        
        for (NSNotification *notification in self.notifications) {
            for (NSNotification *otherNotification in self.notifications) {
                WFAssertEqualNotifications(notification, otherNotification);
            }
        }
    }
}

@end
