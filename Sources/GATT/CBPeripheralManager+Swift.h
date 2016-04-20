//
//  CBPeripheralManager+Swift.h
//  GATT
//
//  Created by Alsey Coleman Miller on 4/20/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

#import <CoreBluetooth/CoreBluetooth.h>

@interface CBPeripheralManager (Swift)

- (nonnull instancetype)initWithSwiftDelegate:(nullable id)delegate
                                        queue:(nullable dispatch_queue_t)queue;

@end
