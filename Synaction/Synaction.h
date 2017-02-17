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

typedef void(^ _Nullable completionBlockPeerID)(MCPeerID * _Nullable error);

@interface Synaction : NSObject <ConnectivityManagerDelegate>

+ (instancetype _Nonnull)sharedManager;


- (void)calculateTimeOffsetWithHostFromStart:(BOOL)resetBools;
- (uint64_t)currentNetworkTime;
- (void)atExactTime:(uint64_t)val runBlock:(dispatch_block_t _Nonnull)block;
- (void)executeBlockWhenPeerCalibrates:(MCPeerID * _Nonnull)peer block:(completionBlockPeerID)completionBlock;
- (void)askPeersToCalculateOffset;
- (void)session:(MCSession * _Nonnull)session didReceiveData:(NSData * _Nonnull)data fromPeer:(MCPeerID * _Nonnull)peerID;

@property (strong, nonatomic) NSMutableArray <MCPeerID*> * _Nullable calibratedPeers;

@end
