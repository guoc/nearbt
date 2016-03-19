//
//  NBTCentralController.m
//  NearBT
//
//  Created by guoc on 13/03/2016.
//  Copyright © 2016 guoc. All rights reserved.
//

#import "NBTCentralController.h"

#import <time.h>

#import "../Constants.h"
#import "oath.h"

@interface NBTCentralController ()
@property (nonatomic) NSNumber *minimumRSSI;
@property (nonatomic) NSUInteger allowedTimeout;
@property (nonatomic) NSMutableSet *discoveredPeripheral; // "You must retain a local copy of the peripheral if any command is to be performed on it."
@property (nonatomic) NSMutableSet *discardedPeripheral;
@property (nonatomic) CBPeripheral *targetPeripheral;
@property (nonatomic) CBCentralManager *centralManager;
@property (nonatomic) NSData *valueData;
@property (nonatomic) dispatch_group_t group;
@property (nonatomic) CBUUID * serviceUUID;
@property (nonatomic) CBUUID * characteristicUUID;
@end

@implementation NBTCentralController

- (instancetype)initWithMinimumRSSI:(NSNumber *)rssi timeout:(NSUInteger)timeout {
    NSLog(@"{{{ NBTCentralController init.");
    self = [super init];
    if (self) {
        self.minimumRSSI = rssi;
        self.allowedTimeout = timeout;
        self.discoveredPeripheral = [[NSMutableSet alloc] init];
        self.discardedPeripheral = [[NSMutableSet alloc] init];
        self.targetPeripheral = nil;
        self.valueData = nil;
    }
    NSLog(@"}}} End of NBTCentralController init.");
    return self;
}

- (NSData *)readValueForCharacteristicUUID:(CBUUID *)characteristicUUID ofServiceUUID:(CBUUID *)serviceUUID {
    NSLog(@"{{{ Trying reading value …");
    self.characteristicUUID = characteristicUUID;
    self.serviceUUID = serviceUUID;
    
    self.group = dispatch_group_create();
    dispatch_group_enter(self.group);
    
    self.centralManager = [[CBCentralManager alloc] initWithDelegate:self queue:dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0)];
    
    long status = dispatch_group_wait(self.group, dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC * self.allowedTimeout));

    self.centralManager.delegate = nil;
    
    NSLog(@"dispatch_group_wait return status: %ld", status);
    
    if (status != 0) {
        NSLog(@"}}} dispatch_group_wait timeout.");
        return nil;
    }
    NSLog(@"}}} End of reading value.");
    return self.valueData;
}

- (void)centralManagerDidUpdateState:(CBCentralManager *)central {
    NSLog(@"{{{ Central manager did update state: %ld", central.state);
    if (self.targetPeripheral) {
        NSLog(@"}}} Target peripheral has been founded, stop.");
        return;
    }
    if (central.state != CBCentralManagerStatePoweredOn) {
        return;
    }
    [central scanForPeripheralsWithServices:nil options:@{CBCentralManagerScanOptionAllowDuplicatesKey: @YES}];
    NSLog(@"}}}");
}

- (void)centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:(NSDictionary<NSString *,id> *)advertisementData RSSI:(NSNumber *)RSSI {
    NSLog(@"{{{ Central manager did discover peripheral: %@, RSSI: %@", peripheral.name, RSSI);
    if (self.targetPeripheral) {
        NSLog(@"}}} Target peripheral has been founded, stop.");
        return;
    }
    if (RSSI.integerValue > -20 || RSSI.integerValue < self.minimumRSSI.integerValue) {
        NSLog(@"}}} RSSI(%@) is invalid.", RSSI);
        return;
    }
    if ([self.discoveredPeripheral containsObject:peripheral] || [self.discardedPeripheral containsObject:peripheral]) {
        NSLog(@"}}} %@ is discovered again, stop.", peripheral.name);
        return;
    } else {
        NSLog(@"Add peripheral in discoveredPeripherals.");
        [self.discoveredPeripheral addObject:peripheral];
    }
    
    NSLog(@"}}} Try connecting …");
    [central connectPeripheral:peripheral options:nil];
}

- (void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral {
    NSLog(@"{{{ Central manager did connect peripheral: %@", peripheral.name);
    if (self.targetPeripheral) {
        NSLog(@"}}} Target peripheral has been founded, stop.");
        return;
    }
    peripheral.delegate = self;
    NSLog(@"}}} Try discover the peripheral's services …");
    [peripheral discoverServices:@[self.serviceUUID]];
}

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverServices:(NSError *)error {
    NSLog(@"{{{ Central manager did discover services %@", peripheral.services);
    if (self.targetPeripheral) {
        NSLog(@"}}} Target peripheral has been founded, stop.");
        return;
    }
    if (error) {
        NSLog(@"}}} Error: %@", error);
        return;
    }
    CBService *targetService = nil;
    for (CBService *service in peripheral.services) {
        if ([service.UUID isEqual:self.serviceUUID]) {
            targetService = service;
            [self.centralManager stopScan];
            break;
        }
    }
    if (targetService) {
        NSLog(@"Target service is found.\n");
        NSLog(@"Current peripheral is stored.\n");
        NSLog(@"}}} Further peripherals discovering, connecting and services discovering will be stopped.");
        self.targetPeripheral = peripheral;
        [peripheral discoverCharacteristics:@[self.characteristicUUID] forService:targetService];
    } else {
        NSLog(@"}}} Target service is not found.");
        [self.discoveredPeripheral removeObject:peripheral];
        [self.discardedPeripheral addObject:peripheral];
    }
}

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverCharacteristicsForService:(CBService *)service error:(NSError *)error {
    NSLog(@"{{{ Central manager did discover characteristics %@", service.characteristics);
    if (error) {
        NSLog(@"}}} Error: %@", error);
        return;
    }
    CBCharacteristic *targetCharacteristic = nil;
    for (CBCharacteristic *characteristic in service.characteristics) {
        if ([characteristic.UUID isEqual:self.characteristicUUID]) {
            targetCharacteristic = characteristic;
            break;
        }
    }
    if (targetCharacteristic) {
        NSLog(@"}}} Target characteristic is found, try reading and subscribing it.");
        [peripheral readValueForCharacteristic:targetCharacteristic];
        [peripheral setNotifyValue:YES forCharacteristic:targetCharacteristic];
    }
}

- (void)peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error {
    NSLog(@"{{{ Peripheral did update value.");
    if (error) {
        NSLog(@"}}} Error: %@", error);
        return;
    }
    self.valueData = characteristic.value;
    NSLog(@"}}} Get target characteristic value: %@", self.valueData);
    if (self.group) {
        dispatch_group_leave(self.group);
        self.group = nil;
    }
    return;
}

@end
