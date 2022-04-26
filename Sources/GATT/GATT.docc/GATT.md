# ``GATT``

Bluetooth Generic Attribute Profile (GATT) for Swift

## Overview

The Generic Attributes (GATT) is the name of the interface used to connect to Bluetooth LE devices. The interface has one or more Bluetooth Services, identified by unique ids, that contain Bluetooth Characteristics also identified by ids.

## Topics

### Central

The GATT client or central sends requests to a server and receives responses (and server-initiated updates) from it. The GATT client does not know anything in advance about the server’s attributes, so it must first inquire about the presence and nature of those attributes by performing service discovery. After completing service discovery, it can then start reading and writing attributes found in the server, as well as receiving server-initiated updates.

- ``CentralManager``
- ``GATTCentral``
- ``GATTCentralOptions``
- ``CentralError``
- ``Peripheral``
- ``AsyncCentralScan``
- ``AsyncCentralNotifications``
- ``ScanData``
- ``AdvertisementData``
- ``ManufacturerSpecificData``
- ``Service``
- ``Characteristic``
- ``CharacteristicProperty``
- ``Descriptor``
- ``AttributePermission``

### Peripheral

The GATT server or peripheral receives requests from a client and sends responses back. It also sends server-initiated updates when configured to do so, and it is the role responsible for storing and making the user data available to the client, organized in attributes.

- ``PeripheralManager``
- ``GATTPeripheral``
- ``GATTPeripheralOptions``
- ``Central``
- ``GATTReadRequest``
- ``GATTWriteRequest``
- ``GATTWriteConfirmation``
