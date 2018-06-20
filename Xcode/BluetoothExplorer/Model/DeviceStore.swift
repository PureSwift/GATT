//
//  DeviceStore.swift
//  BluetoothExplorer
//
//  Created by Alsey Coleman Miller on 6/15/18.
//  Copyright © 2018 PureSwift. All rights reserved.
//

import Foundation
import CoreData
import CoreBluetooth
import Bluetooth
import GATT

public final class DeviceStore {
    
    // MARK: - Properties
    
    /// The managed object context used for caching.
    public let managedObjectContext: NSManagedObjectContext
    
    /// The Bluetooth Low Energy GATT Central this `Store` will use for device requests.
    public let centralManager: CentralManager
        
    /// A convenience variable for the managed object model.
    private let managedObjectModel: NSManagedObjectModel
    
    /// Block for creating the persistent store.
    private let createPersistentStore: (NSPersistentStoreCoordinator) throws -> NSPersistentStore
    
    /// Block for resetting the persistent store.
    private let deletePersistentStore: (NSPersistentStoreCoordinator, NSPersistentStore?) throws -> ()
    
    private let persistentStoreCoordinator: NSPersistentStoreCoordinator
    
    private var persistentStore: NSPersistentStore
    
    /// The managed object context running on a background thread for asyncronous caching.
    private let privateQueueManagedObjectContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
    
    private lazy var centralIdentifier: String = {
        
        return self.centralManager.identifier ?? "org.pureswift.GATT.CentralManager.default"
    }()
    
    // MARK: - Initialization
    
    deinit {
        
        // stop recieving 'didSave' notifications from private context
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name.NSManagedObjectContextDidSave, object: self.privateQueueManagedObjectContext)
        
        NotificationCenter.default.removeObserver(self)
    }
    
    public init(contextConcurrencyType: NSManagedObjectContextConcurrencyType = .mainQueueConcurrencyType,
                createPersistentStore: @escaping (NSPersistentStoreCoordinator) throws -> NSPersistentStore,
                deletePersistentStore: @escaping (NSPersistentStoreCoordinator, NSPersistentStore?) throws -> (),
                centralManager: CentralManager) throws {
        
        // store values
        self.createPersistentStore = createPersistentStore
        self.deletePersistentStore = deletePersistentStore
        self.centralManager = centralManager
        
        // set managed object model
        self.managedObjectModel = DeviceStore.managedObjectModel
        self.persistentStoreCoordinator = NSPersistentStoreCoordinator(managedObjectModel: self.managedObjectModel)
        
        // setup managed object contexts
        self.managedObjectContext = NSManagedObjectContext(concurrencyType: contextConcurrencyType)
        self.managedObjectContext.undoManager = nil
        self.managedObjectContext.persistentStoreCoordinator = persistentStoreCoordinator
        
        self.privateQueueManagedObjectContext.undoManager = nil
        self.privateQueueManagedObjectContext.persistentStoreCoordinator = persistentStoreCoordinator
        self.privateQueueManagedObjectContext.name = "\(type(of: self)) Private Managed Object Context"
        
        // configure CoreData backing store
        self.persistentStore = try createPersistentStore(persistentStoreCoordinator)
        
        // listen for notifications (for merging changes)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(DeviceStore.mergeChangesFromContextDidSaveNotification(_:)),
                                               name: NSNotification.Name.NSManagedObjectContextDidSave,
                                               object: self.privateQueueManagedObjectContext)
    }
    
    // MARK: Requests
    
    /// The default Central managed object.
    public var central: CentralManagedObject {
        
        let context = privateQueueManagedObjectContext
        
        let centralIdentifier = self.centralIdentifier
        
        do {
            
            let managedObjectID: NSManagedObjectID = try context.performErrorBlockAndWait {
                
                let managedObject = try CentralManagedObject.findOrCreate(centralIdentifier, in: context)
                
                if managedObject.objectID.isTemporaryID {
                    
                    try context.save()
                }
                
                return managedObject.objectID
            }
            
            assert(managedObjectID.isTemporaryID == false, "Managed object \(managedObjectID) should be persisted")
            
            return managedObjectContext.object(with: managedObjectID) as! CentralManagedObject
        }
        
        catch { fatalError("Could not cache \(error)") }
    }
    
    /// Scans for nearby devices.
    ///
    /// - Parameter duration: The duration of the scan.
    public func scan(duration: TimeInterval, filterDuplicates: Bool = true) throws {
        
        let end = Date() + duration
        
        let context = privateQueueManagedObjectContext
        
        let centralIdentifier = self.centralIdentifier
        
        centralManager.scan(filterDuplicates: filterDuplicates, shouldContinueScanning: { Date() < end }, foundDevice: { (scanData) in
            
            do {
                
                try context.performErrorBlockAndWait {
                    
                    let central = try CentralManagedObject.findOrCreate(centralIdentifier, in: context)
                    
                    let peripheral = try PeripheralManagedObject.findOrCreate(scanData.peripheral.identifier,
                                                                              in: context)
                    peripheral.isConnected = false
                    peripheral.central = central
                    peripheral.scanData.update(scanData)
                    
                    // save
                    try context.save()
                }
            }
                
            catch {
                dump(error)
                assertionFailure("Could not cache")
                return
            }
        })
    }
    
    public func discoverServices(for peripheral: Peripheral) throws {
        
        // perform BLE operation
        let foundServices = try device(for: peripheral) {
            try centralManager.discoverServices(for: peripheral)
        }
        
        // cache
        let context = privateQueueManagedObjectContext
        
        do {
            
            try context.performErrorBlockAndWait {
                
                guard let peripheralManagedObject = try PeripheralManagedObject.find(peripheral.identifier, in: context)
                    else { assertionFailure("Peripheral \(peripheral) not cached"); return }
                
                // insert new services
                let serviceManagedObjects: [ServiceManagedObject] = try foundServices.map {
                    let managedObject = try ServiceManagedObject.findOrCreate($0.uuid, peripheral: peripheral, in: context)
                    managedObject.isPrimary = $0.isPrimary
                    return managedObject
                }
                
                // remove old services
                peripheralManagedObject.services
                    .filter { serviceManagedObjects.contains($0) == false }
                    .forEach { context.delete($0) }
                
                // save
                try context.save()
            }
        }
            
        catch {
            dump(error)
            assertionFailure("Could not cache")
            return
        }
    }
    
    // MARK: - Private Methods
    
    /// Connects to the device, fetches the data, and performs the action, and disconnects.
    private func device <T> (for peripheral: Peripheral, _ action: () throws -> (T)) throws -> T {
        
        // connect first
        try centralManager.connect(to: peripheral)
        
        defer { centralManager.disconnect(peripheral: peripheral) }
        
        // perform action
        return try action()
    }
    
    // MARK: Notifications
    
    @objc private func mergeChangesFromContextDidSaveNotification(_ notification: Notification) {
        
        self.managedObjectContext.performAndWait {
            
            self.managedObjectContext.mergeChanges(fromContextDidSave: notification)
            
            // manually send notification
            NotificationCenter.default.post(name: .NSManagedObjectContextObjectsDidChange,
                                            object: self.managedObjectContext,
                                            userInfo: notification.userInfo)
        }
    }
}


// MARK: - Extensions

public extension DeviceStore {
    
    public static var managedObjectModel: NSManagedObjectModel {
        
        guard let fileURL = Bundle(for: self).url(forResource: "Model", withExtension: "momd"),
            let model = NSManagedObjectModel(contentsOf: fileURL)
            else { fatalError("Could not load CoreData model file") }
        
        return model
    }
}

// MARK: - Singleton

public extension DeviceStore {
    
    /// The default store.
    public static var shared: DeviceStore {
        
        struct Static {
            
            static let store = try! DeviceStore(createPersistentStore: DeviceStore.createPersistentStore,
                                                deletePersistentStore: DeviceStore.deletePersistentStore,
                                                centralManager: CentralManager(options: [
                                                    CBCentralManagerOptionRestoreIdentifierKey:
                                                        Bundle.main.bundleIdentifier ?? "org.pureswift.GATT.CentralManager"
                                                    ]))
        }
        
        return Static.store
    }
    
    internal static let fileURL: URL = {
        
        let fileManager = FileManager.default
        
        // get cache folder
        
        let cacheURL = try! fileManager.url(for: .cachesDirectory,
                                            in: .userDomainMask,
                                            appropriateFor: nil,
                                            create: false)
        
        
        // get app folder
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "org.pureswift.GATT"
        let folderURL = cacheURL.appendingPathComponent(bundleIdentifier, isDirectory: true)
        
        // create folder if doesnt exist
        var folderExists: ObjCBool = false
        if fileManager.fileExists(atPath: folderURL.path, isDirectory: &folderExists) == false
            || folderExists.boolValue == false {
            
            try! fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        }
        
        let fileURL = folderURL.appendingPathComponent("GATT.sqlite", isDirectory: false)
        
        return fileURL
    }()
    
    internal static func createPersistentStore(_ coordinator: NSPersistentStoreCoordinator) throws -> NSPersistentStore {
        
        func createStore() throws -> NSPersistentStore {
            
            return try coordinator.addPersistentStore(ofType: NSSQLiteStoreType,
                                                      configurationName: nil,
                                                      at: DeviceStore.fileURL,
                                                      options: nil)
        }
        
        do { return try createStore() }
            
        catch {
            
            // delete file
            try DeviceStore.deletePersistentStore(coordinator, nil)
            
            // try again
            return try createStore()
        }
    }
    
    internal static func deletePersistentStore(_ coordinator: NSPersistentStoreCoordinator, _ persistentStore: NSPersistentStore? = nil) throws {
        
        let url = self.fileURL
        
        if FileManager.default.fileExists(atPath: url.path) {
            
            // delete file
            try FileManager.default.removeItem(at: url)
        }
        
        if let persistentStore = persistentStore {
            
            try coordinator.remove(persistentStore)
        }
    }
}
