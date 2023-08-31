# Synaction
A library that allows you to perform code on multiple devices at the same time, offline. 

Synaction allows you to execute a block of code on different and multiple iDevices, all connected through the multipeer connectivity framework, at an (almost) exact time. It uses mach time and calculates the precise offset between the host device, and it's peers.

# How to

Add the library and header file into your project, they can be found in the `Synaction Product` folder. And import `Synaction.h` wherever you'll be using the class.

## Network Setup 
Bundled with Synaction is ConnectivityManager, a MultipeerConnectivity wrapper. Synaction uses it to send data between devices.

1. Call `+sharedInstance` on Synaction to initialize it and the connectiivty manager.
2. On the host device call `-setupBrowser` and on the peers call `-advertiseSelfInSessions:YES`.
3. To present the connection interface, on the view controller present the `browser` (property of the Connectivity Manager).

## Synaction Setup
1. First get an instance of Synaction by calling `+sharedManager`.
2. To execute code at the same time, first calculate the offset with the host, by calling `- calculateTimeOffsetWithHost` on the peer device(s) or `- askPeersToCalculateOffset:` on the host.
3. Then use `- atExactTime:(uint64_t)val runBlock:(dispatch_block_t _Nonnull)block` to perform `block` at `val` nano time. `val` should be a value in nanoseconds. 
4. To accurately calculate this value you can get the current mach time in nano seconds with `- currentNetworkTime` for network adjusted time (synced) and `- currentTime` for local device time.

##Documentation
Documentation for the various functions will (hopefully) eventually be written. Meanwhile, the function names are pretty self explanatory, otherwise post an issue. If you'd like to contribute to the docs just submit a pull request.

# Credits
Both the connectivity manager, and the core components of the mach time calculations were found online and modified.
[Connectivity Manager](http://stackoverflow.com/a/20907425/2210825 "Stackoverflow Answer")

Mach Time Article: I'm currently not able to find the article from where I pulled this. If you're the author, or have doubts of where it comes from please open an issue!

# License
Check License file.
