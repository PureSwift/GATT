//
//  CBSwiftCentralManager.m
//  GATT
//
//  Created by Alsey Coleman Miller on 4/20/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

#import "CBSwiftCentralManager.h"

@implementation CBSwiftCentralManager

- (instancetype)initWithCentralManager:(CBCentralManager *)centralManager delegate:(id<CBSwiftCentralManagerDelegate>) delegate
{
    self = [super init];
    if (self) {
        
        self.delegate = delegate;
        self.centralManager = centralManager;
        self.centralManager.delegate = self;
    }
    return self;
}

- (void)centralManagerDidUpdateState:(CBCentralManager *)central;
{
    [_delegate centralManagerDidUpdateState];
}

- (void)centralManager:(CBCentralManager *)central willRestoreState:(NSDictionary<NSString *, id> *)state
{
    [_delegate centralManagerWillRestore:state];
}

- (void)centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:(NSDictionary<NSString *, id> *)advertisementData RSSI:(NSNumber *)RSSI
{
    [_delegate centralManagerDidDiscover: peripheral];
}

- (void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral
{
    [_delegate centralManagerDidConnect:peripheral];
}

- (void)centralManager:(CBCentralManager *)central didFailToConnectPeripheral:(CBPeripheral *)peripheral error:(nullable NSError *)error
{
    [_delegate centralManagerDidFailToConnect:peripheral error:error];
}

- (void)centralManager:(CBCentralManager *)central didDisconnectPeripheral:(CBPeripheral *)peripheral error:(nullable NSError *)error
{
    [_delegate centralManagerDidDisconnect:peripheral error:error];
}

@end
