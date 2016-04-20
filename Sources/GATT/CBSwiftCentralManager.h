//
//  CBSwiftCentralManager.h
//  GATT
//
//  Created by Alsey Coleman Miller on 4/20/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

@import Foundation;
@import CoreBluetooth;

NS_ASSUME_NONNULL_BEGIN

@protocol CBSwiftCentralManagerDelegate;

/// Swift 3.0 compatible central manager.
@interface CBSwiftCentralManager: NSObject <CBCentralManagerDelegate>

@property (nonatomic, nonnull) CBCentralManager *centralManager;

@property (weak, nonatomic, nullable) id<CBSwiftCentralManagerDelegate> delegate;

- (instancetype)initWithCentralManager:(CBCentralManager *)centralManager delegate:(id<CBSwiftCentralManagerDelegate>) delegate NS_DESIGNATED_INITIALIZER;

@end

@protocol CBSwiftCentralManagerDelegate <NSObject>

- (void)centralManagerDidUpdateState;

@optional

- (void)centralManagerWillRestore:(NSDictionary<NSString *, id> *)state;

- (void)centralManagerDidDiscover:(CBPeripheral *)peripheral;

- (void)centralManagerDidConnect:(CBPeripheral *)peripheral;

- (void)centralManagerDidFailToConnect:(CBPeripheral *)peripheral error:(NSError *)error;

- (void)centralManagerDidDisconnect:(CBPeripheral *)peripheral error:(nullable NSError *)error;

@end

NS_ASSUME_NONNULL_END
