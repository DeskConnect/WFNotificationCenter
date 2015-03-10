# WFNotificationCenter

`WFDistributedNotificationCenter` is similar to `NSDistributedNotificationCenter`, but it is designed to work within app groups on iOS. This means that you can post notifications from your app to your extensions and vice versa.

## Architecture

The traditional model for distributed notifications is client-server, where applications are the clients and a daemon (`distnoted`, `notifyd`, etc) acts as the server. The server receives notifications from its clients and distributes them appropriately

This model doesn't work on iOS. There isn't a daemon that supports posting rich notifications, and you can't write your own. With `WFDistributedNotificationCenter`, the connections are decentralized. When applications want to listen for a notification, they create a local mach server and update a shared registry with the mach port name. Clients posting notifications read this registry and send notifications to the appropriate process. This communication happens using the public `CFMessagePort` API, and the shared registry is currently stored in shared memory.

## Notes

- **This is not production ready yet**
- It works
- It handles process suspension gracefully (and delivers notifications upon resume)
- The central coordination mechanism can be improved a ton (named semaphores and shared memory aren't as clean as I had hoped)
- The over-the-wire data format is not set in stone
- The class interface is not set in stone
- The `object` property on `NSNotification` is unused, but may be implemented in the future (with the requirement that it be an `NSString` like with `NSDistributedNotificationCenter`)

## License

WFNotificationCenter is available under the MIT license. See the LICENSE file for more info.
