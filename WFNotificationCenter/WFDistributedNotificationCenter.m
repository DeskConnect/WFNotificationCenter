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

@interface WFDistributedNotificationCenter ()
- (void)receivedNotification:(NSNotification *)notification;
@end

static NSString * const WFNotificationNameKey = @"Name";
static NSString * const WFNotificationUserInfoKey = @"UserInfo";
static SInt32 const WFDistributedNotificationMessage = 1;

CFDataRef WFServerCallback(CFMessagePortRef local, SInt32 msgid, CFDataRef data, void *info) {
    WFDistributedNotificationCenter *center = (__bridge WFDistributedNotificationCenter *)info;
    if (msgid == WFDistributedNotificationMessage) {
        NSDictionary *dictionary = [NSKeyedUnarchiver unarchiveObjectWithData:(__bridge NSData *)data];
        [center receivedNotification:[NSNotification notificationWithName:[dictionary objectForKey:WFNotificationNameKey] object:nil userInfo:[dictionary objectForKey:WFNotificationUserInfoKey]]];
    }
    
    return NULL;
}

@implementation WFDistributedNotificationCenter {
    NSString *_memoryName;
    NSString *_semaphoreName;
    NSString *_serverName;
    int _fd;
    sem_t *_semaphore;
    
    NSMapTable *_targetsByName;
    
    CFMessagePortRef _server;
    NSMapTable *_connections;
}

#pragma mark - Threading

+ (dispatch_queue_t)receiveNotificationQueue {
    static dispatch_queue_t receiveNotificationQueue = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        receiveNotificationQueue = dispatch_queue_create("WFDistributedNotificationCenter.receive", DISPATCH_QUEUE_SERIAL);
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

- (instancetype)init {
    return [self initWithSecurityApplicationGroupIdentifier:nil];
}

- (instancetype)initWithSecurityApplicationGroupIdentifier:(NSString *)groupIdentifier {
    NSParameterAssert(groupIdentifier);
    self = [super init];
    if (!self) {
        return nil;
    }
    
    _memoryName = _semaphoreName = [groupIdentifier stringByAppendingFormat:@"/wfdnc"];
    _serverName = [groupIdentifier stringByAppendingFormat:@".%@.%i", NSStringFromClass([WFDistributedNotificationCenter class]), getpid()];
    _targetsByName = [NSMapTable strongToStrongObjectsMapTable];
    _connections = [NSMapTable strongToStrongObjectsMapTable];
    
    if ((_fd = shm_open([_memoryName UTF8String], O_RDWR | O_CREAT, 0644)) == -1) {
        NSLog(@"Error opening shared memory segment with name \"%@\": %@", _memoryName, [[NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil] localizedFailureReason]);
        return nil;
    }
    
    if ((_semaphore = sem_open([_semaphoreName UTF8String], O_CREAT, 0644, 1)) == SEM_FAILED) {
        NSLog(@"Error opening named semaphore with name \"%@\": %@", _semaphoreName, [[NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil] localizedFailureReason]);
        return nil;
    }
    
    return self;
}

- (void)dealloc {
    if (_server) {
        CFMessagePortInvalidate(_server);
        CFRelease(_server);
    }
    for (NSString *portName in _connections) {
        CFMessagePortInvalidate((__bridge CFMessagePortRef)[_connections objectForKey:portName]);
    }
    close(_fd);
    shm_unlink([_memoryName UTF8String]);
    sem_close(_semaphore);
    sem_unlink([_semaphoreName UTF8String]);
}

#pragma mark - Coordination

- (NSDictionary *)portsByNotification {
    NSDictionary *portsByNotification = nil;
    
    sem_wait(_semaphore);
    struct stat shm_stat;
    fstat(_fd, &shm_stat);
    if (shm_stat.st_size > 0) {
        void *bytes = mmap(NULL, shm_stat.st_size, PROT_READ, (MAP_FILE | MAP_SHARED), _fd, 0);
        NSData *readData = [NSData dataWithBytesNoCopy:bytes length:MIN(strlen(bytes), shm_stat.st_size) freeWhenDone:NO];
        portsByNotification = [NSJSONSerialization JSONObjectWithData:readData options:0 error:nil];
        readData = nil;
        munmap(bytes, shm_stat.st_size);
    }
    sem_post(_semaphore);
    
    return portsByNotification;
}

- (void)mutatePortsByNotification:(void (^)(NSMutableDictionary *portsByNotification))mutator {
    if (!mutator)
        return;
    
    sem_wait(_semaphore);
    NSMutableDictionary *portsByNotification = [NSMutableDictionary new];
    
    struct stat shm_stat;
    fstat(_fd, &shm_stat);
    if (shm_stat.st_size > 0) {
        void *bytes = mmap(NULL, shm_stat.st_size, PROT_READ, (MAP_FILE | MAP_SHARED), _fd, 0);
        NSData *readData = [NSData dataWithBytesNoCopy:bytes length:MIN(strlen(bytes), shm_stat.st_size) freeWhenDone:NO];
        [portsByNotification addEntriesFromDictionary:[NSJSONSerialization JSONObjectWithData:readData options:NSJSONReadingMutableContainers error:nil]];
        readData = nil;
        munmap(bytes, shm_stat.st_size);
    }
    
    mutator(portsByNotification);
    
    NSData *writeData = (portsByNotification.count ? [NSJSONSerialization dataWithJSONObject:portsByNotification options:0 error:nil] : nil);
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

#pragma mark - Registration

- (void)removeObserver:(id)observer {
    for (NSString *name in _targetsByName)
        [[_targetsByName objectForKey:name] removeObjectForKey:observer];
}

- (void)removeObserver:(id)observer name:(NSString *)aName {
    [[_targetsByName objectForKey:aName] removeObjectForKey:observer];
}

- (void)addObserver:(id)observer selector:(SEL)aSelector name:(NSString *)aName {
    NSMapTable *selectorsByTarget = ([_targetsByName objectForKey:aName] ?: [NSMapTable weakToStrongObjectsMapTable]);
    NSMutableSet *selectors = ([NSMutableSet setWithArray:[selectorsByTarget objectForKey:observer]] ?: [NSMutableSet new]);
    [selectors addObject:NSStringFromSelector(aSelector)];
    [selectorsByTarget setObject:selectors forKey:observer];
    [_targetsByName setObject:selectorsByTarget forKey:aName];
    
    if (!_server) {
        CFMessagePortContext context = {0, (__bridge void *)self, NULL, NULL, NULL};
        _server = CFMessagePortCreateLocal(NULL, (__bridge CFStringRef)_serverName, &WFServerCallback, &context, NULL);
        CFMessagePortSetDispatchQueue(_server, [[self class] receiveNotificationQueue]);
    }
    
    [self mutatePortsByNotification:^(NSMutableDictionary *portsByNotification) {
        NSMutableSet *ports = ([NSMutableSet setWithArray:[portsByNotification objectForKey:aName]] ?: [NSMutableSet new]);
        [ports addObject:_serverName];
        [portsByNotification setObject:[ports allObjects] forKey:aName];
    }];
}

#pragma mark - Posting

- (void)postNotificationName:(NSString *)aName {
    [self postNotification:[NSNotification notificationWithName:aName object:nil]];
}

- (void)postNotificationName:(NSString *)aName userInfo:(NSDictionary *)aUserInfo {
    [self postNotification:[NSNotification notificationWithName:aName object:nil userInfo:aUserInfo]];
}

- (void)postNotification:(NSNotification *)notification {
    NSMutableArray *portNames = [[self.portsByNotification objectForKey:notification.name] mutableCopy];
    
    if ([portNames containsObject:_serverName]) {
        dispatch_async([[self class] receiveNotificationQueue], ^{
            [self receivedNotification:notification];
        });
    }
    
    [portNames removeObject:_serverName];
    
    if (portNames.count) {
        NSData *data = [NSKeyedArchiver archivedDataWithRootObject:[NSDictionary dictionaryWithObjectsAndKeys:notification.name, WFNotificationNameKey, notification.userInfo, WFNotificationUserInfoKey, nil]];
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:[self methodSignatureForSelector:@selector(sendData:toPortsNamed:)]];
        [invocation setSelector:@selector(sendData:toPortsNamed:)];
        [invocation setArgument:(void *)&data atIndex:2];
        [invocation setArgument:(void *)&portNames atIndex:3];
        [invocation retainArguments];
        [invocation performSelector:@selector(invokeWithTarget:) onThread:[[self class] postNotificationThread] withObject:self waitUntilDone:NO];
    }
}

- (void)sendData:(NSData *)data toPortsNamed:(NSArray *)portNames {
    NSMutableSet *invalidPortNames = [NSMutableSet new];
    
    for (NSString *portName in portNames) {
        CFMessagePortRef port = (__bridge CFMessagePortRef)[_connections objectForKey:portName];
        if (!port) {
            port = CFMessagePortCreateRemote(NULL, (__bridge CFStringRef)portName);
            if (port) {
                [_connections setObject:(__bridge_transfer id)port forKey:portName];
            }
        }
        
        if (!port || !CFMessagePortIsValid(port)) {
            [_connections removeObjectForKey:portName];
            [invalidPortNames addObject:portName];
            continue;
        }
        
        CFMessagePortSendRequest(port, WFDistributedNotificationMessage, (__bridge CFDataRef)data, 1000, 0, NULL, NULL);
    }
    
    [self mutatePortsByNotification:^(NSMutableDictionary *portsByNotification) {
        for (NSString *notification in portsByNotification) {
            [[portsByNotification objectForKey:notification] removeObjectsInArray:[invalidPortNames allObjects]];
        }
    }];
}

#pragma mark - Receiving

- (void)receivedNotification:(NSNotification *)notification {
    NSMapTable *selectorsByTarget = [_targetsByName objectForKey:notification.name];
    for (id target in selectorsByTarget) {
        for (NSString *selectorString in [selectorsByTarget objectForKey:target]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            [target performSelector:NSSelectorFromString(selectorString) withObject:notification];
#pragma clang diagnostic pop
        }
    }
}

@end
