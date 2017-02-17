//
//  Synaction.m
//  Synaction
//
//  Created by Georges Kanaan on 11/02/2017.
//  Copyright © 2017 Georges Kanaan. All rights reserved.
//

#import "Synaction.h"

// Frameworks
#import <AVFoundation/AVFoundation.h>
#import <mach/mach_time.h>

@interface Synaction () {
  int64_t hostTimeOffset;
  int64_t tempHostTimeOffset;
  BOOL secondPing;
  BOOL calibrated;
}

@property (strong, nonatomic) ConnectivityManager *connectivityManager;

@end

@implementation Synaction

+ (instancetype _Nonnull)sharedManager {
  static Synaction *sharedManager = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    sharedManager = [[self alloc] init];
    sharedManager.connectivityManager = [ConnectivityManager sharedManagerWithDisplayName:[[UIDevice currentDevice] name]];
    sharedManager->tempHostTimeOffset = 0;
    sharedManager->secondPing = NO;
    sharedManager->calibrated = NO;
    sharedManager.calibratedPeers = [NSMutableArray new];
  });
  
  return sharedManager;
}

#pragma mark - Network Time Sync
// Host
- (void)executeBlockWhenPeerCalibrates:(MCPeerID * _Nonnull)peer block:(completionBlockPeerID)completionBlock {
  [[NSNotificationCenter defaultCenter] addObserverForName:@"peerCalibrated" object:self.calibratedPeers queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification * _Nonnull notification) {
    if ([notification.userInfo[@"calibratedPeer"] isEqual:peer]) {
      completionBlock(peer);
    }
  }];
}

- (void)askPeersToCalculateOffset {
  // Send the "sync" command to peers to trigger their offset calculations.
  NSMutableDictionary *payloadDic = [[NSMutableDictionary alloc] initWithDictionary:@{@"command": @"sync"}];
  NSData *payload = [NSKeyedArchiver archivedDataWithRootObject:payloadDic];
  
  [self.connectivityManager sendData:payload toPeers:self.connectivityManager.allPeers reliable:YES];
  
  // Clear the list of calibrated peers
  [self.calibratedPeers removeAllObjects];
}

// Meant for speaker
- (void)calculateTimeOffsetWithHostFromStart:(BOOL)resetBools {
  if (resetBools) {// These bools are used to track the state of calculation. They must be set to no to go through a full calibration.
    calibrated = NO;
    secondPing = NO;
  }
  
  hostTimeOffset = 0;
  self.connectivityManager.delegate = self;// Needed for reply calls.
  
  NSMutableDictionary *payloadDic = [[NSMutableDictionary alloc] initWithDictionary:@{@"command": @"syncPing",
                                                                                      @"timeSent": [NSNumber numberWithUnsignedLongLong:[self currentNetworkTime]]
                                                                                      }];
  
  NSData *payload = [NSKeyedArchiver archivedDataWithRootObject:payloadDic];
  
  [self.connectivityManager sendData:payload toPeers:self.connectivityManager.allPeers reliable:YES];// Speakers are only connected to the host.
}

- (uint64_t)currentNetworkTime {
  uint64_t baseTime = mach_absolute_time();
  // Convert from ticks to nanoseconds:
  static mach_timebase_info_data_t s_timebase_info;
  if (s_timebase_info.denom == 0) {
    mach_timebase_info(&s_timebase_info);
  }
  
  uint64_t timeNanoSeconds = (baseTime * s_timebase_info.numer) / s_timebase_info.denom;
  return timeNanoSeconds + hostTimeOffset;
}

- (void)atExactTime:(uint64_t)val runBlock:(dispatch_block_t _Nonnull)block {
  // Use the most accurate timing possible to trigger an event at the specified DTime.
  // This is much more accurate than dispatch_after(...), which has a 10% "leeway" by default.
  // However, this method will use battery faster as it avoids most timer coalescing.
  // Use as little as necessary.
  dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, DISPATCH_TIMER_STRICT, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0));
  dispatch_source_set_event_handler(timer, ^{
    dispatch_source_cancel(timer); // one shot timer
    while ((int64_t)(val - [self currentNetworkTime]) > 1) {
      [NSThread sleepForTimeInterval:0];
    }
    block();
  });
  // Now, we employ a dirty trick:
  // Since even with DISPATCH_TIMER_STRICT there can be about 1ms of inaccuracy, we set the timer to
  // fire 1.3ms too early, then we use an until(time) { sleep(); } loop to delay until the exact time
  // that we wanted. This takes us from an accuracy of ~1ms to an accuracy of ~0.01ms, i.e. two orders
  // of magnitude improvement. However, of course the downside is that this will block the main thread
  // for 1.3ms.
  dispatch_time_t at_time = dispatch_time(DISPATCH_TIME_NOW, val - [self currentNetworkTime] - 1300000);
  dispatch_source_set_timer(timer, at_time, DISPATCH_TIME_FOREVER /*one shot*/, 0 /* minimal leeway */);
  dispatch_resume(timer);
}

- (void)session:(MCSession *)session didReceiveData:(NSData *)data fromPeer:(MCPeerID *)peerID {
  NSDictionary *payload = [NSKeyedUnarchiver unarchiveObjectWithData:data];
  
  // Check if the host is asking us to sync
  if ([payload[@"command"] isEqualToString:@"sync"]) {
    if (calibrated) {// No need to restart the process if we haven't calibrated yet
      [self calculateTimeOffsetWithHostFromStart:YES];
    }
    
    return;
    
  } else if ([payload[@"command"] isEqualToString:@"syncDone"]) {
    [self.calibratedPeers addObject:peerID];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"peerCalibrated" object:self.calibratedPeers userInfo:@{@"calibratedPeer": peerID}];
    
    return;
  } else if ([payload[@"command"] isEqualToString:@"syncPing"]) {// This is done on the peer with which we are calculating the offset (Host).
    NSMutableDictionary *payloadDic = [[NSMutableDictionary alloc] initWithDictionary:@{@"command": @"syncPong",
                                                                                        @"timeReceived": [NSNumber numberWithUnsignedLongLong:[self currentNetworkTime]],
                                                                                        @"timeSent": payload[@"timeSent"]
                                                                                        }];
    
    NSData *payload = [NSKeyedArchiver archivedDataWithRootObject:payloadDic];
    
    [self.connectivityManager sendData:payload toPeers:@[peerID] reliable:YES];// Speakers are only connected to the host.
    
    return;
    
    // This is done on the person who callled calculateTimeOffsetWithHost (Player).
  } else if ([payload[@"command"] isEqualToString:@"syncPong"] && !calibrated) {
    if (secondPing) {
      hostTimeOffset = ((NSNumber*)payload[@"timeReceived"]).unsignedLongLongValue - (([self currentNetworkTime] + ((NSNumber*)payload[@"timeSent"]).unsignedLongLongValue)/2);
      
      // Check that two calculated offsets don't differ by much, do the average.
      if (llabs(tempHostTimeOffset - hostTimeOffset) > 5000) {// Error margin in nano seconds between the two calculated offsets
        NSLog(@"margin to big recalibrating: %lli", llabs(tempHostTimeOffset - hostTimeOffset));
        
        // Offsets are above error margin, restart process.
        [self calculateTimeOffsetWithHostFromStart:YES];
        
      } else {
        // Offsets meet the acceptable error margin.
        secondPing = NO; // Reset for next ping
        calibrated = YES; // No calibrating twice.
        
        NSLog(@"Accepted margin: %lli", llabs(tempHostTimeOffset - hostTimeOffset));
        
        // Let the host know we calibrated
        NSMutableDictionary *payloadDic = [[NSMutableDictionary alloc] initWithDictionary:@{@"command": @"syncDone"}];
        NSData *payload = [NSKeyedArchiver archivedDataWithRootObject:payloadDic];
        
        [self.connectivityManager sendData:payload toPeers:self.connectivityManager.allPeers reliable:YES];
      }
      
    } else {
      secondPing = YES;
      tempHostTimeOffset = ((NSNumber*)payload[@"timeReceived"]).unsignedLongLongValue - (([self currentNetworkTime] + ((NSNumber*)payload[@"timeSent"]).unsignedLongLongValue)/2);
      
      [self calculateTimeOffsetWithHostFromStart:NO];// We do the average of the two.
    }
    
    return;
  }
}

@end
