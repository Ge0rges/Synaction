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
  NSMutableArray *calculatedOffsets;
  BOOL isCalibrating;
}

@property (strong, nonatomic) ConnectivityManager *connectivityManager;

@property (nonatomic) int64_t hostTimeOffset;

@end

@implementation Synaction

+ (instancetype _Nonnull)sharedManager {
  static Synaction *sharedManager = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    sharedManager = [[self alloc] init];
    sharedManager.connectivityManager = [ConnectivityManager sharedManagerWithDisplayName:[[UIDevice currentDevice] name]];
    sharedManager.connectivityManager.synaction = sharedManager;
    sharedManager.hostTimeOffset = 0;
    sharedManager.numberOfCalibrations = 1;
    sharedManager.calibratedPeers = [NSMutableSet new];
    sharedManager->calculatedOffsets = [NSMutableArray new];
    
  });
  
  return sharedManager;
}


#pragma mark - Network Time Sync
// Host
- (void)executeBlockWhenAllPeersCalibrate:(NSArray <MCPeerID *> * _Nonnull)peers block:(calibrationBlock)completionBlock {
  // Check if these peers already had the time to calibrate
  NSSet *peersSet = [NSSet setWithArray:peers];
  
  if ([peersSet isEqualToSet:self.calibratedPeers]) {// Already calibrated
    completionBlock(peers);
    return;
  }
  
  // They didn't. Register to receive notifications. Execute when all are calibrated.
  __block id observer = [[NSNotificationCenter defaultCenter] addObserverForName:@"peerCalibrated" object:self.calibratedPeers queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification * _Nonnull notification) {
    
    __block BOOL executeBlock = YES;
    
    // Check that every object in peers is contained in calibratedPeers
    [peers enumerateObjectsUsingBlock:^(MCPeerID * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
      if (executeBlock) {// Make sure a NO doesn't get switched to a YES.
        executeBlock = [self.calibratedPeers containsObject:obj];
      }
      
      *stop = !executeBlock;// Stop if executeBlock is NO.
    }];
    
    // Check if we should execute the block
    if (executeBlock) {
      completionBlock(peers);
      [[NSNotificationCenter defaultCenter] removeObserver:observer];
    }
  }];
}

- (void)executeBlockWhenEachPeerCalibrates:(NSArray <MCPeerID *> * _Nonnull)peers block:(calibrationBlock)completionBlock {
  // Check if these peers already had the time to calibrate
  NSSet *peersSet = [NSSet setWithArray:peers];
  
  for (MCPeerID *peer in peersSet) {
    if ([self.calibratedPeers containsObject:peer]) {// Already calibrated
      completionBlock(@[peer]);
      return;
    }
  }
  
  // They didn't. Register to receive notifications. Execute when each one is calibrated.
  __block id observer = [[NSNotificationCenter defaultCenter] addObserverForName:@"peerCalibrated" object:self.calibratedPeers queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification * _Nonnull notification) {
    for (MCPeerID *peer in peersSet) {
      if ([self.calibratedPeers containsObject:peer]) {// Already calibrated
        completionBlock(@[peer]);
        return;
      }
    }
  }];
  
  // Unsubscribe when every one calibrates.
  [self executeBlockWhenAllPeersCalibrate:peers block:^(NSArray<MCPeerID *> * _Nullable peers) {
    [[NSNotificationCenter defaultCenter] removeObserver:observer];
  }];
}

- (void)askPeersToCalculateOffset:(NSArray <MCPeerID*>* _Nonnull)peers {
  // Send the "sync" command to peers to trigger their offset calculations.
  NSMutableDictionary *payloadDic = [[NSMutableDictionary alloc] initWithDictionary:@{@"command": @"sync"}];
  NSData *payload = [NSKeyedArchiver archivedDataWithRootObject:payloadDic];
  
  [self.connectivityManager sendData:payload toPeers:peers reliable:YES];
}

// Meant for speakers.
- (void)calculateTimeOffsetWithHost {
  if (!isCalibrating) {
    isCalibrating = YES;// Used to track the calibration
    [calculatedOffsets removeAllObjects];// Remove all previously calculated offsets
    self.hostTimeOffset = 0;// Reset the host offset so we can calibrate properly
    
    // Send a ping per calibration required (the average will be done later)
    for (int i=0; i<self.numberOfCalibrations; i++) {
      
      NSMutableDictionary *payloadDic = [[NSMutableDictionary alloc] initWithDictionary:@{@"command": @"syncPing",
                                                                                          @"timeSent": [NSNumber numberWithUnsignedLongLong:[self currentNetworkTime]]
                                                                                          }];
      NSData *payload = [NSKeyedArchiver archivedDataWithRootObject:payloadDic];
      
      [self.connectivityManager sendData:payload toPeers:self.connectivityManager.allPeers reliable:YES];
    }
    
    // Handle 0 calibrations
    if (self.numberOfCalibrations == 0) {
      isCalibrating = NO;
      self.hostTimeOffset = 0;
      
      // Let the host know we calibrated
      NSMutableDictionary *payloadDic = [[NSMutableDictionary alloc] initWithDictionary:@{@"command": @"syncDone"}];
      NSData *payload = [NSKeyedArchiver archivedDataWithRootObject:payloadDic];
      
      [self.connectivityManager sendData:payload toPeers:self.connectivityManager.allPeers reliable:YES];
    }
  }
}

- (uint64_t)currentNetworkTime {// https://developer.apple.com/library/content/qa/qa1398/_index.html
  uint64_t baseTime = mach_absolute_time();
  
  // Convert from ticks to nanoseconds:
  static mach_timebase_info_data_t sTimebaseInfo;
  if (sTimebaseInfo.denom == 0) {// Check if timebase is initialize
    mach_timebase_info(&sTimebaseInfo);
  }
  
  uint64_t timeNanoSeconds = baseTime * sTimebaseInfo.numer / sTimebaseInfo.denom;
  return (int64_t)timeNanoSeconds - self.hostTimeOffset;
}

- (void)atExactTime:(uint64_t)val runBlock:(dispatch_block_t _Nonnull)block {
  if (val <= [self currentNetworkTime]) {// The value has already passed execute immediately.
    block();
    return;
  }
  
  // Use the most accurate timing possible to trigger an event at the specified DTime.
  // This is much more accurate than dispatch_after(...), which has a 10% "leeway" by default.
  // However, this method will use battery faster as it avoids most timer coalescing.
  // Use as little as necessary.
  dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, DISPATCH_TIMER_STRICT, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0));
  dispatch_source_set_event_handler(timer, ^{
    dispatch_source_cancel(timer); // one shot timer
    while (val > [self currentNetworkTime]) {
      sleep(0);
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
    [self calculateTimeOffsetWithHost];
    
    return;
    
  } else if ([payload[@"command"] isEqualToString:@"syncDone"]) {
    [self.calibratedPeers addObject:peerID];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"peerCalibrated" object:self.calibratedPeers userInfo:@{@"calibratedPeer": peerID}];
    
    return;
  } else if ([payload[@"command"] isEqualToString:@"syncPing"]) {// This is done on the peer with which we are calculating the offset (Host).
    NSMutableDictionary *payloadDic = [[NSMutableDictionary alloc] initWithDictionary:@{@"command": @"syncPong",
                                                                                        @"timeReceived": [NSNumber numberWithUnsignedLongLong:[self currentNetworkTime]],
                                                                                        @"timeSent": payload[@"timeSent"],
                                                                                        }];
    
    NSData *payload = [NSKeyedArchiver archivedDataWithRootObject:payloadDic];
    
    [self.connectivityManager sendData:payload toPeers:@[peerID] reliable:YES];// Speakers are only connected to the host.
    
    return;
    
    // This is done on the person who callled calculateTimeOffsetWithHost (Player).
  } else if ([payload[@"command"] isEqualToString:@"syncPong"]) {
    
    // Calculate the offset and add it to the calculated offsets.
    uint64_t timePingSent = ((NSNumber*)payload[@"timeSent"]).unsignedLongLongValue;
    uint64_t timeHostReceivedPing = ((NSNumber*)payload[@"timeReceived"]).unsignedLongLongValue;
    
    //uint64_t latencyWithHost = ([self currentNetworkTime] - timePingSent)/2;// Calculates the estimated latency for one way travel
    
    int64_t calculatedOffset = ((int64_t)[self currentNetworkTime] + (int64_t)timePingSent - (2*(int64_t)timeHostReceivedPing))/2; // WAY 1. Best because it doesn't depend on latency
    //calculatedOffset2 = (int64_t)latencyWithHost - (int64_t)timeHostReceivedPing + (int64_t)timePingSent;// WAY 2
    //calculatedOffset3 = -(int64_t)latencyWithHost - (int64_t)timeHostReceivedPing + (int64_t)[self currentNetworkTime];// WAY 3
    
    [calculatedOffsets addObject:[NSNumber numberWithLongLong:calculatedOffset]];
    
    if (calculatedOffsets.count == self.numberOfCalibrations) {// If is the last value, calculate the average of all offsets.
      int64_t numeratorForAverage = 0;
      for (NSNumber *calculatedOffset in calculatedOffsets) {
        numeratorForAverage += calculatedOffset.longLongValue;
      }
      
      self.hostTimeOffset = numeratorForAverage/(int64_t)self.numberOfCalibrations;
      
      // Let the host know we calibrated
      NSMutableDictionary *payloadDic = [[NSMutableDictionary alloc] initWithDictionary:@{@"command": @"syncDone"}];
      NSData *payload = [NSKeyedArchiver archivedDataWithRootObject:payloadDic];
      
      [self.connectivityManager sendData:payload toPeers:@[peerID] reliable:YES];
      
      // Update the bool
      isCalibrating = NO;
    }
    
    return;
  }
}

- (void)session:(MCSession* _Nonnull)session peer:(MCPeerID* _Nonnull)peerID didChangeState:(MCSessionState)state {
  // Remove the disconnected peer from the calibratde peer list if it's there.
  if (state == MCSessionStateNotConnected) {
    [self.calibratedPeers removeObject:peerID];
    isCalibrating = NO;
    self.hostTimeOffset = 0;
  }
}

@end
