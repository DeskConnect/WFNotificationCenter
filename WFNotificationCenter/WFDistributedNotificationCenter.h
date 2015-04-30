//
//  WFDistributedNotificationCenter.h
//  WFNotificationCenter
//
//  Created by Conrad Kramer on 3/5/15.
//  Copyright (c) 2015 DeskConnect, Inc. All rights reserved.
//

#import <Foundation/Foundation.h>

/**
 `WFDistributedNotificationCenter` is a notification center that works within app groups on iOS.
 
 It behaves just like `NSDistributedNotificationCenter`, which in turn behaves just like `NSNotificationCenter`, with the following differences:
 
 - NSNotification `object` properties must be `NSString` objects, if used.
 - All objects in a notification's `userInfo` dictionary must adhere to `NSSecureCoding`.
 - Notifications are always delivered asynchronously, even within the same process
 */
@interface WFDistributedNotificationCenter : NSObject

/**
 Initializes and returns a notification center object that can communicate with other notification center objects that share the same `groupIdentifier`.
 
 @param groupIdentifier The application group identifier shared by the code you want to communicate between.
 
 @return The initialized notification center object, or `nil` if the object couldn't be created.
 
 @note Your app must have a `com.apple.security.application-groups` entitlement for the specified application group.
 */
- (instancetype)initWithSecurityApplicationGroupIdentifier:(NSString *)groupIdentifier NS_DESIGNATED_INITIALIZER;

///------------------------------------------------
/// @name Adding Observers
///------------------------------------------------

/**
 Adds a target-selector pair to the reciever's dispatch table that is called when a notification is received matching the specified name and object. This method registers the observer with the set of property list classes as the allowed classes.
 
 @param observer The object registering as an observer. The observer is not retained, and must not be `nil`.
 @param aSelector The selector of the message sent to `observer` when a notification is received. Must not be `0`. The method specified by `aSelector` must have either zero arguments or one argument (of type `NSNotification`).
 @param aName The notification name for which to register the observer. Only notifications with this name are delivered to the observer. When `nil`, the observer receives notifications of any name.
 @param anObject The notification object for which to register the observer. Only notifications with the same object are delivered to the observer. When `nil`, the observer receives notifications with any object.
 
 @see -addObserver:selector:name:object:allowedClasses:
 */
- (void)addObserver:(id)observer selector:(SEL)aSelector name:(NSString *)aName object:(NSString *)anObject;

/**
 Adds a target-selector pair to the reciever's dispatch table that is called when a notification is received matching the specified name and object.
 
 @param observer The object registering as an observer. The observer is not retained, and must not be `nil`.
 @param aSelector The selector of the message sent to `observer` when a notification is received. Must not be `0`. The method specified by `aSelector` must have either zero arguments or one argument (of type `NSNotification`).
 @param aName The notification name for which to register the observer. Only notifications with this name are delivered to the observer. When `nil`, the observer receives notifications of any name.
 @param anObject The notification object for which to register the observer. Only notifications with the same object are delivered to the observer. When `nil`, the observer receives notifications with any object.
 @param allowedClasses The set of classes allowed for secure coding. The receiver uses this set of classes to decode the `userInfo` dictionary of the received notification. If an empty set or `nil` is specified, the set of property list classes is used. If a notification is received that contains classes not found in this parameter, the `userInfo` dictionary is dropped and a warning is logged.
 
 @see [Whitelisting a Class for Use Inside Containers](https://developer.apple.com/library/mac/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingXPCServices.html#//apple_ref/doc/uid/10000172i-SW6-SW26)
 */
- (void)addObserver:(id)observer selector:(SEL)aSelector name:(NSString *)aName object:(NSString *)anObject allowedClasses:(NSSet *)allowedClasses;

/**
 Adds a block to the reciever's dispatch table that is called when a notification is received matching the specified name and object. This method registers the block with the set of property list classes as the allowed classes.
 
 @param name The notification name for which to register the block. Only notifications with this name are used to add the block to the operation queue. When `nil`, the block will be added to the operation queue for notifications of any name.
 @param obj The notification object for which to register the block. Only notifications with the same object are used to add the block to the operation queue. When `nil`, the block will be added to the operation queue for notifications with any object.
 @param queue The operation queue to which the block should be added. If you pass `nil`, the block is run on a background queue.
 @param block The block to be executed when a notification is received. The block is copied by the receiver and held until the observer registration is removed. The block has no return value and takes one argument: the notification.
 
 @return An opaque object to act as the observer. The `block` and `queue` parameters will both be retained until the observer is removed using `removeObserver:`.
 
 @see -addObserverForName:object:allowedClasses:queue:usingBlock:
 */
- (id<NSObject>)addObserverForName:(NSString *)name object:(id)obj queue:(NSOperationQueue *)queue usingBlock:(void (^)(NSNotification *note))block;

/**
 Adds a block to the reciever's dispatch table that is called when a notification is received matching the specified name and object.
 
 @param name The notification name for which to register the block. Only notifications with this name are used to add the block to the operation queue. When `nil`, the block will be added to the operation queue for notifications of any name.
 @param obj The notification object for which to register the block. Only notifications with the same object are used to add the block to the operation queue. When `nil`, the block will be added to the operation queue for notifications with any object.
 @param allowedClasses The set of classes allowed for secure coding. The receiver uses this set of classes to decode the `userInfo` dictionary of the received notification. If an empty set or `nil` is specified, the set of property list classes is used. If a notification is received that contains classes not found in this parameter, the `userInfo` dictionary is dropped and a warning is logged.
 @param queue The operation queue to which the block should be added. If you pass `nil`, the block is run on a background queue.
 @param block The block to be executed when a notification is received. The block is copied by the receiver and held until the observer registration is removed. The block has no return value and takes one argument: the notification.
 
 @return An opaque object to act as the observer. The `block` and `queue` parameters will both be retained until the observer is removed using `removeObserver:`.
 
 @see [Whitelisting a Class for Use Inside Containers](https://developer.apple.com/library/mac/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingXPCServices.html#//apple_ref/doc/uid/10000172i-SW6-SW26)
 */
- (id<NSObject>)addObserverForName:(NSString *)name object:(id)obj allowedClasses:(NSSet *)allowedClasses queue:(NSOperationQueue *)queue usingBlock:(void (^)(NSNotification *note))block;

///------------------------------------------------
/// @name Posting Notifications
///------------------------------------------------

/**
 Posts the given notification to all registered observers.
 
 @param notification The notification to post. This value must not be `nil`. The `userInfo` dictionary must conform to `NSSecureCoding`.
 */
- (void)postNotification:(NSNotification *)notification;

/**
 Creates a notification with a given name and object and posts it to all registered observers.

 @param aName The name of the notification. Must not be `nil`.
 @param anObject The object of the notification. Can be `nil`.
 */
- (void)postNotificationName:(NSString *)aName object:(NSString *)anObject;

/**
 Creates a notification with a given name, object and userInfo dictionary and posts it to all registered observers.
 
 @param aName The name of the notification. Must not be `nil`.
 @param anObject The object of the notification. Can be `nil`.
 @param aUserInfo The user info of the notification. Must conform to `NSSecureCoding`. Can be `nil`.
 */
- (void)postNotificationName:(NSString *)aName object:(NSString *)anObject userInfo:(NSDictionary *)aUserInfo;

///------------------------------------------------
/// @name Removing Observers
///------------------------------------------------

/**
 Removes all the entries specifying the given observer from the receiver’s dispatch table.
 
 @param observer The observer to remove. Must not be `nil`, or this method will have no effect.
 */
- (void)removeObserver:(id)observer;

/**
 Removes the entries from the reciever's dispatch table that match the specified observer, name, and object.

 @param observer Observer to remove from the dispatch table. Specify an observer to remove only entries for this observer. Must not be `nil`, or this method will have no effect.
 @param aName Name of the notification to remove entries for from from dispatch table. Specify a notification name to remove only entries that have this notification name. When `nil`, observers with all notification names are considered for removal.
 @param anObject Object of the notification to remove entries for from the dispatch table. Specify a notification object to remove only entries that specify this object. When `nil`, observers with all notification objects are considered for removal.
 */
- (void)removeObserver:(id)observer name:(NSString *)aName object:(id)anObject;

@end
