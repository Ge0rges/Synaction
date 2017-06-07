//
//  Synaction.h
//  Synaction
//
//  Created by Georges Kanaan on 11/02/2017.
//  Copyright © 2017 Georges Kanaan. All rights reserved.
//

// Frameworks
#import <Foundation/Foundation.h>
#import <MultipeerConnectivity/MultipeerConnectivity.h>

// Managers
@protocol ConnectivityManagerDelegate <NSObject>

@optional
- (void)session:(MCSession* _Nonnull)session didFinishReceivingResourceWithName:(NSString* _Nonnull)resourceName fromPeer:(MCPeerID* _Nonnull)peerID atURL:(NSURL* _Nonnull)localURL withError:(NSError* _Nullable)error;
- (void)session:(MCSession* _Nonnull)session didStartReceivingResourceWithName:(NSString* _Nonnull)resourceName fromPeer:(MCPeerID* _Nonnull)peerID withProgress:(NSProgress* _Nonnull)progress;
- (void)session:(MCSession * _Nonnull)session didReceiveData:(NSData * _Nonnull)data fromPeer:(MCPeerID * _Nonnull)peerID;
- (void)session:(MCSession* _Nonnull)session peer:(MCPeerID* _Nonnull)peerID didChangeState:(MCSessionState)state;

- (void)browserViewControllerWasCancelled:(MCBrowserViewController * _Nonnull)browserViewController;
- (void)browserViewControllerDidFinish:(MCBrowserViewController * _Nonnull)browserViewController;

@end


@interface ConnectivityManager : NSObject <MCSessionDelegate, MCAdvertiserAssistantDelegate, MCBrowserViewControllerDelegate>

@property (nonatomic, assign) id<ConnectivityManagerDelegate> _Nullable delegate;
@property (nonatomic, assign) id<ConnectivityManagerDelegate> _Nullable synaction;
@property (nonatomic, strong) MCBrowserViewController * _Nullable browser;
@property (nonatomic, strong) NSMutableArray * _Nullable sessions;

+ (instancetype _Nullable)sharedManagerWithDisplayName:(NSString * _Nonnull )displayName;

- (MCSession * _Nullable)availableSession;
- (NSMutableArray * _Nullable)allPeers;

- (void)setupBrowser;
- (void)advertiseSelfInSessions:(BOOL)advertise;

- (void)sendData:(NSData * _Nonnull)data toPeers:(NSArray * _Nonnull)peerIDs reliable:(BOOL)reliable;
- (void)sendResourceAtURL:(NSURL * _Nonnull)assetUrl withName:(NSString * _Nonnull)name toPeers:(NSArray * _Nonnull)peerIDs withCompletionHandler:(void(^ _Nullable)(NSError* _Nullable __strong))handler;

@end

typedef void(^ _Nullable calibrationBlock)(NSArray <MCPeerID *> * _Nullable peers);

@interface Synaction : NSObject <ConnectivityManagerDelegate>

+ (instancetype _Nonnull)sharedManager;// Use this to get an instance of Synaction

- (void)askPeersToCalculateOffset:(NSArray <MCPeerID*>* _Nonnull)peers;// Asks the peers to call -calculateTimeOffsetWithHost, when completed the block of -executeBlockWhenPeerCalibrates will be called on host.
- (void)calculateTimeOffsetWithHost:(MCPeerID * _Nonnull)hostPeer;// Calculate the time difference in nanoseconds between us and the host device.
- (uint64_t)currentTime;// Current clock time. If on host this is equal to currentNetworkTime
- (uint64_t)currentNetworkTime;// The current host time adjusted for offset (offset = 0 if host).
- (void)atExactTime:(uint64_t)val runBlock:(dispatch_block_t _Nonnull)block;// Run block at the exact host adjusted time val adjusted
- (void)executeBlockWhenAllPeersCalibrate:(NSArray <MCPeerID *> * _Nonnull)peers block:(calibrationBlock)completionBlock;// Once EVERY peer in the array calibrates this will be called
- (void)executeBlockWhenEachPeerCalibrates:(NSArray <MCPeerID *> * _Nonnull)peers block:(calibrationBlock)completionBlock;// FOR EACH peer in the array that calibrates this will be called

@property (strong, nonatomic) NSMutableSet <MCPeerID*> * _Nullable calibratedPeers;// Array of all peers that have already calibrated
@property (nonatomic, readonly) uint64_t maxNumberOfCalibrations;// The number of calibrations to be used to calculate the averaga offset offset
@property (nonatomic, readonly) uint64_t latencyWithHost;// The calculated latency between the peer and host. Only on peer.
@property (nonatomic, readonly) int64_t hostTimeOffset;// The calculated offset between the peer and the host. Only on peer.

@end
