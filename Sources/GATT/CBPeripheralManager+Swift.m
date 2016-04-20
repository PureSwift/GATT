//
//  CBPeripheralManager+Swift.m
//  GATT
//
//  Created by Alsey Coleman Miller on 4/20/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

#import "CBPeripheralManager+Swift.h"

@implementation CBPeripheralManager (Swift)

- (instancetype)initWithSwiftDelegate:(nullable id)swiftDelegate
                                queue:(nullable dispatch_queue_t)queue
{
    
    Class class = NSClassFromString(@"CBPeripheralManager");
    
    return [[class alloc] initWithDelegate: swiftDelegate queue: queue];
}

@end
