//
//  WFDistributedNotificationCenter.m
//  WorkflowKit
//
//  Created by Conrad Kramer on 3/5/15.
//  Copyright (c) 2015 DeskConnect. All rights reserved.
//

#import "WFDistributedNotificationCenter.h"

#include <sys/mman.h>
#include <sys/stat.h>
#include <semaphore.h>

#pragma mark - Serialization

static NSString * const WFNotificationArchiveNameKey = @"WFNotificationName";
static NSString * const WFNotificationArchiveUserInfoKey = @"WFNotificationUserInfo";
static NSString * const WFNotificationArchiveObjectKey = @"WFNotificationObject";

static NSData *WFArchivedDataFromNotification(NSNotification *notification) {
    NSCAssert(notification.object == nil || [notification.object isKindOfClass:[NSString class]], @"Notification object must be of class NSString");
    NSCAssert(notification.userInfo == nil || [NSPropertyListSerialization propertyList:notification.userInfo isValidForFormat:NSPropertyListBinaryFormat_v1_0], @"Notification userInfo object must be a valid property list");
    NSMutableData *data = [NSMutableData new];
    NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc] initForWritingWithMutableData:data];
    [archiver setOutputFormat:NSPropertyListBinaryFormat_v1_0];
    [archiver setRequiresSecureCoding:YES];
    [archiver encodeObject:notification.name forKey:WFNotificationArchiveNameKey];
    [archiver encodeObject:notification.userInfo forKey:WFNotificationArchiveUserInfoKey];
    [archiver encodeObject:notification.object forKey:WFNotificationArchiveObjectKey];
    [archiver finishEncoding];
    return [data copy];
}

static NSNotification *WFNotificationFromArchivedData(NSData *data) {
    NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData:data];
    [unarchiver setRequiresSecureCoding:YES];
    NSString *name = [unarchiver decodeObjectOfClass:[NSString class] forKey:WFNotificationArchiveNameKey];
    NSDictionary *userInfo = [unarchiver decodePropertyListForKey:WFNotificationArchiveUserInfoKey];
    NSString *object = [unarchiver decodeObjectOfClass:[NSString class] forKey:WFNotificationArchiveObjectKey];
    return [NSNotification notificationWithName:name object:object userInfo:userInfo];
}

#pragma mark - Server Callback

@interface WFDistributedNotificationCenter ()
- (void)receivedData:(NSData *)data withMessageId:(SInt32)messageId fromPort:(CFMessagePortRef)port;
@end

CFDataRef WFNotificationServerCallback(CFMessagePortRef local, SInt32 msgid, CFDataRef dataRef, void *info) {
    NSData *data = CFBridgingRelease(dataRef);
    for (WFDistributedNotificationCenter *center in (__bridge NSHashTable *)info) {
        [center receivedData:data withMessageId:msgid fromPort:local];
    }
    return NULL;
}

static SInt32 const WFDistributedNotificationPostMessageId = 1;
static NSString * const WFDistributedNotificationCatchAllKey = @"*";

@implementation WFDistributedNotificationCenter {
    NSString *_memoryName;
    NSString *_semaphoreName;
    NSString *_serverName;
    int _fd;
    sem_t *_semaphore;
    
    NSMutableDictionary *_observers;
    
    CFMessagePortRef _server;
}

#pragma mark - Threading

+ (dispatch_queue_t)receiveNotificationQueue {
    static dispatch_queue_t receiveNotificationQueue = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        receiveNotificationQueue = dispatch_queue_create("com.deskconnect.WFDistributedNotificationCenter.receive", DISPATCH_QUEUE_SERIAL);
    });
    return receiveNotificationQueue;
}

+ (void)postNotificationThreadEntryPoint:(id)__unused object {
    @autoreleasepool {
        [[NSThread currentThread] setName:NSStringFromClass(self)];
        
        NSRunLoop *runLoop = [NSRunLoop currentRunLoop];
        [runLoop addPort:[NSMachPort port] forMode:NSDefaultRunLoopMode];
        [runLoop run];
    }
}

+ (NSThread *)postNotificationThread {
    static NSThread *postNotificationThread = nil;
    static dispatch_once_t oncePredicate;
    dispatch_once(&oncePredicate, ^{
        postNotificationThread = [[NSThread alloc] initWithTarget:self selector:@selector(postNotificationThreadEntryPoint:) object:nil];
        [postNotificationThread start];
    });
    
    return postNotificationThread;
}

#pragma mark - Lifecycle

+ (NSHashTable *)activeCentersForServerName:(NSString *)serverName {
    static NSMutableDictionary *activeCentersByServerName = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        activeCentersByServerName = [NSMutableDictionary new];
    });
    NSHashTable *activeCenters = ([activeCentersByServerName objectForKey:serverName] ?: [NSHashTable weakObjectsHashTable]);
    [activeCentersByServerName setObject:activeCenters forKey:serverName];
    return activeCenters;
}

- (instancetype)init {
    return [self initWithSecurityApplicationGroupIdentifier:nil];
}

- (instancetype)initWithSecurityApplicationGroupIdentifier:(NSString *)groupIdentifier {
    NSParameterAssert(groupIdentifier.length);
    self = [super init];
    if (!self) {
        return nil;
    }
    
    _memoryName = _semaphoreName = [groupIdentifier stringByAppendingFormat:@"/wfdnc"];
    _serverName = [groupIdentifier stringByAppendingFormat:@".%@.%i", NSStringFromClass([self class]), getpid()];
    _observers = [NSMutableDictionary new];
    
    if ((_fd = shm_open([_memoryName UTF8String], O_RDWR | O_CREAT, 0644)) == -1) {
        NSLog(@"%@: Error opening shared memory segment with name \"%@\": %@", self, _memoryName, [[NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil] localizedFailureReason]);
        return nil;
    }
    
    if ((_semaphore = sem_open([_semaphoreName UTF8String], O_CREAT, 0644, 1)) == SEM_FAILED) {
        NSLog(@"%@: Error opening named semaphore with name \"%@\": %@", self, _semaphoreName, [[NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil] localizedFailureReason]);
        return nil;
    }
    
    return self;
}

- (void)dealloc {
    if (_server) {
        NSHashTable *activeCenters = [WFDistributedNotificationCenter activeCentersForServerName:_serverName];
        if ([activeCenters containsObject:self] && activeCenters.count == 1) {
            CFMessagePortInvalidate(_server);
        }
        CFRelease(_server);
        [activeCenters removeObject:self];
    }
    close(_fd);
    shm_unlink([_memoryName UTF8String]);
    sem_close(_semaphore);
    sem_unlink([_semaphoreName UTF8String]);
}

#pragma mark - Port Registry

- (NSDictionary *)portRegistry {
    NSDictionary *portRegistry = nil;
    
    sem_wait(_semaphore);
    struct stat shm_stat;
    fstat(_fd, &shm_stat);
    if (shm_stat.st_size > 0) {
        void *bytes = mmap(NULL, shm_stat.st_size, PROT_READ, (MAP_FILE | MAP_SHARED), _fd, 0);
        NSData *readData = [NSData dataWithBytesNoCopy:bytes length:MIN(strlen(bytes), shm_stat.st_size) freeWhenDone:NO];
        portRegistry = [NSJSONSerialization JSONObjectWithData:readData options:0 error:nil];
        readData = nil;
        munmap(bytes, shm_stat.st_size);
    }
    sem_post(_semaphore);
    
    return portRegistry;
}

- (void)mutatePortRegistry:(void (^)(NSMutableDictionary *portRegistry))mutator {
    if (!mutator)
        return;
    
    sem_wait(_semaphore);
    NSMutableDictionary *portRegistry = [NSMutableDictionary new];
    
    struct stat shm_stat;
    fstat(_fd, &shm_stat);
    if (shm_stat.st_size > 0) {
        void *bytes = mmap(NULL, shm_stat.st_size, PROT_READ, (MAP_FILE | MAP_SHARED), _fd, 0);
        NSData *readData = [NSData dataWithBytesNoCopy:bytes length:MIN(strlen(bytes), shm_stat.st_size) freeWhenDone:NO];
        [portRegistry addEntriesFromDictionary:[NSJSONSerialization JSONObjectWithData:readData options:NSJSONReadingMutableContainers error:nil]];
        readData = nil;
        munmap(bytes, shm_stat.st_size);
    }
    
    mutator(portRegistry);
    
    NSData *writeData = (portRegistry.count ? [NSJSONSerialization dataWithJSONObject:portRegistry options:0 error:nil] : nil);
    ftruncate(_fd, writeData.length);
    fstat(_fd, &shm_stat);
    if (writeData.length) {
        void *bytes = mmap(NULL, shm_stat.st_size, (PROT_READ | PROT_WRITE), (MAP_FILE | MAP_SHARED), _fd, 0);
        memset(bytes, 0, shm_stat.st_size);
        memcpy(bytes, writeData.bytes, writeData.length);
        munmap(bytes, shm_stat.st_size);
    }
    sem_post(_semaphore);
}

- (void)removePortsFromRegistry:(NSSet *)portNames forNotificationName:(NSString *)aName object:(NSString *)anObject {
    [self mutatePortRegistry:^(NSMutableDictionary *portRegistry) {
        for (NSString *observerName in [portRegistry allKeys]) {
            if (!aName || [observerName isEqualToString:aName]) {
                NSMutableDictionary *portsByObject = [portRegistry objectForKey:observerName];
                for (NSString *observerObject in [portsByObject allKeys]) {
                    NSMutableSet *ports = [portsByObject objectForKey:observerObject];
                    if (!anObject || [observerObject isEqualToString:anObject]) {
                        for (NSString *portName in portNames)
                            [ports removeObject:portName];
                    }
                    if (!ports.count)
                        [portsByObject removeObjectForKey:observerObject];
                }
                if (!portsByObject.count)
                    [portRegistry removeObjectForKey:observerName];
            }
        }
    }];
}

- (void)addPortsToRegistry:(NSSet *)portNames forNotificationName:(NSString *)aName object:(NSString *)anObject {
    [self mutatePortRegistry:^(NSMutableDictionary *portRegistry) {
        NSMutableDictionary *portsByObject = ([portRegistry objectForKey:(aName ?: WFDistributedNotificationCatchAllKey)] ?: [NSMutableDictionary new]);
        NSMutableSet *ports = ([NSMutableSet setWithArray:[portsByObject objectForKey:(anObject ?: WFDistributedNotificationCatchAllKey)]] ?: [NSMutableSet new]);
        [ports addObject:_serverName];
        [portsByObject setObject:[ports allObjects] forKey:(anObject ?: WFDistributedNotificationCatchAllKey)];
        [portRegistry setObject:portsByObject forKey:(aName ?: WFDistributedNotificationCatchAllKey)];
    }];
}

#pragma mark - Registration

- (void)removeObserver:(id)observer {
    [self removeObserver:observer name:nil object:nil];
}

- (void)removeObserver:(id)observer name:(NSString *)aName object:(NSString *)anObject {
    if (!observer)
        return;
    
    for (NSString *notificationName in [_observers allKeys]) {
        NSMutableDictionary *targetsByObject = [_observers objectForKey:notificationName];
        if (!aName || [notificationName isEqualToString:aName]) {
            for (NSString *notificationObject in [targetsByObject allKeys]) {
                NSMapTable *selectorsByTarget = [targetsByObject objectForKey:notificationObject];
                if (!anObject || [anObject isEqualToString:notificationObject]) {
                    [selectorsByTarget removeObjectForKey:observer];
                }
                if (!selectorsByTarget.count) {
                    [targetsByObject removeObjectForKey:notificationObject];
                }
            }
        }
        if (!targetsByObject.count) {
            [_observers removeObjectForKey:notificationName];
        }
    }
    
    if (!_observers.count && _server) {
        NSHashTable *activeCenters = [WFDistributedNotificationCenter activeCentersForServerName:_serverName];
        if ([activeCenters containsObject:self] && activeCenters.count == 1) {
            CFMessagePortInvalidate(_server);
            [self removePortsFromRegistry:[NSSet setWithObject:_serverName] forNotificationName:nil object:nil];
        }
        CFRelease(_server);
        _server = NULL;
        [activeCenters removeObject:self];
    }
}

- (void)addObserver:(id)observer selector:(SEL)aSelector name:(NSString *)aName object:(NSString *)anObject {
    if (!observer || !aSelector)
        return;
    
    NSMutableDictionary *targetsByObject = ([_observers objectForKey:(aName ?: WFDistributedNotificationCatchAllKey)] ?: [NSMutableDictionary new]);
    NSMapTable *selectorsByTarget = ([targetsByObject objectForKey:(anObject ?: WFDistributedNotificationCatchAllKey)] ?: [NSMapTable weakToStrongObjectsMapTable]);
    NSMutableSet *selectors = ([selectorsByTarget objectForKey:observer] ?: [NSMutableSet new]);
    [selectors addObject:NSStringFromSelector(aSelector)];
    [selectorsByTarget setObject:selectors forKey:observer];
    [targetsByObject setObject:selectorsByTarget forKey:(anObject ?: WFDistributedNotificationCatchAllKey)];
    [_observers setObject:targetsByObject forKey:(aName ?: WFDistributedNotificationCatchAllKey)];
    
    if (!_server) {
        NSHashTable *activeCenters = [WFDistributedNotificationCenter activeCentersForServerName:_serverName];
        [activeCenters addObject:self];
        CFMessagePortContext context = {0, (__bridge void *)activeCenters, NULL, NULL, NULL};
        _server = CFMessagePortCreateLocal(NULL, (__bridge CFStringRef)_serverName, &WFNotificationServerCallback, &context, NULL);
        NSAssert(_server != NULL, @"%@: Error: The notification server could not be established, is the app group identifier set correctly?", self);
        CFMessagePortSetDispatchQueue(_server, [WFDistributedNotificationCenter receiveNotificationQueue]);
    }
    
    [self addPortsToRegistry:[NSSet setWithObject:_serverName] forNotificationName:aName object:anObject];
}

#pragma mark - Posting

- (void)postNotificationName:(NSString *)aName object:(NSString *)anObject {
    [self postNotification:[NSNotification notificationWithName:aName object:anObject]];
}

- (void)postNotificationName:(NSString *)aName object:(NSString *)anObject userInfo:(NSDictionary *)aUserInfo {
    [self postNotification:[NSNotification notificationWithName:aName object:anObject userInfo:aUserInfo]];
}

- (void)postNotification:(NSNotification *)notification {
    NSAssert(notification.object == nil || [notification.object isKindOfClass:[NSString class]], @"%@: Notification object must be of class NSString", self);
    NSData *data = WFArchivedDataFromNotification(notification);
    
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:[self methodSignatureForSelector:@selector(distributeNotification:data:)]];
    [invocation setSelector:@selector(distributeNotification:data:)];
    [invocation setArgument:&notification atIndex:2];
    [invocation setArgument:&data atIndex:3];
    [invocation retainArguments];
    [invocation performSelector:@selector(invokeWithTarget:) onThread:[WFDistributedNotificationCenter postNotificationThread] withObject:self waitUntilDone:NO];
}

- (void)distributeNotification:(NSNotification *)notification data:(NSData *)data {
    NSMutableSet *portNames = [NSMutableSet new];
    NSDictionary *portRegistry = self.portRegistry;
    for (NSString *portNotificationName in portRegistry) {
        if ([portNotificationName isEqualToString:notification.name] || [portNotificationName isEqualToString:WFDistributedNotificationCatchAllKey]) {
            NSDictionary *portsByObject = [portRegistry objectForKey:portNotificationName];
            for (NSString *portObject in portsByObject) {
                if ([portObject isEqualToString:notification.object] || [portObject isEqualToString:WFDistributedNotificationCatchAllKey]) {
                    [portNames addObjectsFromArray:[portsByObject objectForKey:portObject]];
                }
            }
        }
    }
    
    if (!portNames.count)
        return;
    
    NSMutableSet *invalidPortNames = [NSMutableSet new];
    
    for (NSString *portName in portNames) {
        CFMessagePortRef port =  CFMessagePortCreateRemote(NULL, (__bridge CFStringRef)portName);
        if (!port || !CFMessagePortIsValid(port)) {
            [invalidPortNames addObject:portName];
            continue;
        }
        
        SInt32 status = CFMessagePortSendRequest(port, WFDistributedNotificationPostMessageId, (__bridge CFDataRef)data, 1000, 0, NULL, NULL);
        if (status != kCFMessagePortSuccess) {
            NSLog(@"%@: Error: could not post notification to port \"%@\" with error code %i", self, portName, status);
        }
        
        CFMessagePortInvalidate(port);
        CFRelease(port);
    }
    
    [self removePortsFromRegistry:invalidPortNames forNotificationName:nil object:nil];
}

#pragma mark - Receiving

- (void)receivedData:(NSData *)data withMessageId:(SInt32)messageId fromPort:(CFMessagePortRef)port {
    if (messageId == WFDistributedNotificationPostMessageId) {
        [self receivedNotification:WFNotificationFromArchivedData(data)];
    }
}

- (void)receivedNotification:(NSNotification *)notification {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    NSAssert(notification.object == nil || [notification.object isKindOfClass:[NSString class]], @"%@: Notification object must be of class NSString", self);
    for (NSString *observerNotificationName in _observers) {
        if ([observerNotificationName isEqualToString:notification.name] || [observerNotificationName isEqualToString:WFDistributedNotificationCatchAllKey]) {
            NSMutableDictionary *observerTargetsByObject = [_observers objectForKey:observerNotificationName];
            for (NSString *observerObject in observerTargetsByObject) {
                if ([notification.object isEqualToString:observerObject] || [observerObject isEqualToString:WFDistributedNotificationCatchAllKey]) {
                    NSMapTable *selectorsByTarget = [observerTargetsByObject objectForKey:observerObject];
                    for (id target in selectorsByTarget) {
                        for (NSString *selectorString in [selectorsByTarget objectForKey:target]) {
                            [target performSelector:NSSelectorFromString(selectorString) withObject:notification];
                        }
                    }
                }
            }
        }
    }
#pragma clang diagnostic pop
}

@end
