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
#import "ConnectivityManager.h"

@interface Synaction : NSObject <ConnectivityManagerDelegate>

+ (instancetype _Nonnull)sharedManager;


- (void)calculateTimeOffsetWithHost;
- (uint64_t)currentTime;
- (void)atExactTime:(uint64_t)val runBlock:(dispatch_block_t _Nonnull)block;

- (void)session:(MCSession * _Nonnull)session didReceiveData:(NSData * _Nonnull)data fromPeer:(MCPeerID * _Nonnull)peerID;

@end
