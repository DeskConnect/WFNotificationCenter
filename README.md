# WFNotificationCenter

`WFDistributedNotificationCenter` is similar to `NSDistributedNotificationCenter`, but it is designed to work within app groups on iOS. This means that you can post notifications from your app to your extensions and vice versa.

## Architecture

The traditional model for distributed notifications is client-server, where applications are the clients and a daemon (`distnoted`, `notifyd`, etc) acts as the server. The server receives notifications from its clients and distributes them appropriately

This model doesn't work on iOS. There isn't a daemon that supports posting rich notifications, and you can't write your own. With `WFDistributedNotificationCenter`, the connections are decentralized. When applications want to listen for a notification, they create a local mach server and update a shared registry with the mach port name. Clients posting notifications read this registry and send notifications to the appropriate process. This communication happens using the public `CFMessagePort` API, and the shared registry is currently stored in shared memory.

## Notes

- **This is not production ready quite yet**
- This is not meant for cross-app usage (it is not designed to be runtime compatible across versions)
- It handles process suspension gracefully (and delivers notifications upon resume)
- Test coverage is getting there
- The central coordination mechanism needs improvements (named semaphores have serious issues)

## License

WFNotificationCenter is available under the MIT license. See the LICENSE file for more info.
