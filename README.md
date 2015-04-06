# WFNotificationCenter

`WFDistributedNotificationCenter` is a notification center for communicating between your app and your extensions.

## Features

- Works between any process in the same application group
- API compatible with `NSNotificationCenter`
- Supports notifications with rich `userInfo` dictionaries
- Handles process suspension gracefully (and delivers notifications upon resume)

## Usage

```objc
WFDistributedNotificationCenter *center = [[WFDistributedNotificationCenter alloc] initWithSecurityApplicationGroupIdentifier:@"group.test"];

[center postNotificationName:@"UpdatedStuff" object:nil userInfo:@{@"ChangedIds": @[@3,@4,@10]}];
```

## Installation

### Manually

Add `WFDistributedNotificationCenter.h` and `WFDistributedNotificationCenter.m` into your project.

## Architecture

The traditional model for distributed notifications is client-server, where applications are the clients and a daemon (`distnoted`, `notifyd`, etc) acts as the server. The server receives notifications from its clients and distributes them appropriately

This model doesn't work on iOS. There isn't a daemon that supports posting rich notifications, and you can't write your own. With `WFDistributedNotificationCenter`, the connections are decentralized. When applications want to listen for a notification, they create a local mach server and update a shared registry with the mach port name. Clients posting notifications read this registry and send notifications to the appropriate process. This communication happens using the public `CFMessagePort` API, and the shared registry is currently stored in the app group container.

## Notes

- It is not meant to be used between two separate apps yet, only between an app and its extensions (it is not designed to be runtime compatible across versions)
- It allows sending any object in the `userInfo` dictionary that adheres to `NSSecureCoding`, provided that the observer specifies the class in `allowedClasses`
- Test coverage is incomplete, but being worked on

## License

WFNotificationCenter is available under the MIT license. See the LICENSE file for more info.
