//
//  CBCentralManager+Swift.m
//  GATT
//
//  Created by Alsey Coleman Miller on 4/20/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

#import "CBCentralManager+Swift.h"

@implementation CBCentralManager (Swift)

- (instancetype)initWithSwiftDelegate:(nullable id)swiftDelegate
                                queue:(nullable dispatch_queue_t)queue
{
    
    Class class = NSClassFromString(@"CBCentralManager");
    
    return [[class alloc] initWithDelegate: swiftDelegate queue: queue];
}

@end
