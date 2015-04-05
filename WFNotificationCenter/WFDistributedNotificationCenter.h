//
//  WFDistributedNotificationCenter.h
//  WorkflowKit
//
//  Created by Conrad Kramer on 3/5/15.
//  Copyright (c) 2015 DeskConnect. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface WFDistributedNotificationCenter : NSObject

- (instancetype)initWithSecurityApplicationGroupIdentifier:(NSString *)groupIdentifier NS_DESIGNATED_INITIALIZER;

- (void)addObserver:(id)observer selector:(SEL)aSelector name:(NSString *)aName object:(NSString *)anObject;
- (id<NSObject>)addObserverForName:(NSString *)name object:(id)obj queue:(NSOperationQueue *)queue usingBlock:(void (^)(NSNotification *note))block;

- (void)postNotification:(NSNotification *)notification;
- (void)postNotificationName:(NSString *)aName object:(NSString *)anObject;
- (void)postNotificationName:(NSString *)aName object:(NSString *)anObject userInfo:(NSDictionary *)aUserInfo;

- (void)removeObserver:(id)observer;
- (void)removeObserver:(id)observer name:(NSString *)aName object:(id)anObject;

@end
