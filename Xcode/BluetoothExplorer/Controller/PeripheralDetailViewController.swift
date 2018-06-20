//
//  PeripheralDetailViewController.swift
//  BluetoothExplorer
//
//  Created by Alsey Coleman Miller on 6/20/18.
//  Copyright © 2018 PureSwift. All rights reserved.
//

import Foundation
import UIKit
import CoreData
import Bluetooth
import GATT

final class ServicesViewController: TableViewController {
    
    // MARK: - Properties
    
    public var peripheral: PeripheralManagedObject!
    
    // MARK: - Methods
    
    override func configureView() {
        
        self.title = peripheral.scanData.advertisementData.localName ?? peripheral.identifier
    }
    
    override func newFetchedResultController() -> NSFetchedResultsController<NSManagedObject> {
        
        guard let peripheral = self.peripheral
            else { fatalError("View controller not configured") }
        
        // configure fetched results controller
        let predicate = NSPredicate(format: "%K == %@",
                                    #keyPath(ServiceManagedObject.peripheral),
                                    peripheral)
        
        let sort = [NSSortDescriptor(key: #keyPath(ServiceManagedObject.uuid), ascending: false)]
        let context = DeviceStore.shared.managedObjectContext
        let fetchedResultsController = NSFetchedResultsController(ServiceManagedObject.self,
                                                                  delegate: self,
                                                                  predicate: predicate,
                                                                  sortDescriptors: sort,
                                                                  context: context)
        fetchedResultsController.fetchRequest.fetchBatchSize = 30
        
        return fetchedResultsController
    }
    
    override func reloadData() {
        
        // configure table view and update UI
        scanStart = Date()
        
        // create FRC
        super.reloadData()
        
        // scan
        let scanDuration = self.scanDuration
        performActivity({ try DeviceStore.shared.scan(duration: scanDuration) },
                        completion: { (viewController, _) in viewController.endRefreshing() })
    }
    
    private subscript (indexPath: IndexPath) -> PeripheralManagedObject {
        
        guard let managedObject = self.fetchedResultsController?.object(at: indexPath) as? PeripheralManagedObject
            else { fatalError("Invalid type") }
        
        return managedObject
    }
    
    private func configure(cell: UITableViewCell, at indexPath: IndexPath) {
        
        let peripheral = self[indexPath]
        
        if let localName = peripheral.scanData.advertisementData.localName {
            
            cell.textLabel?.text = localName
            cell.detailTextLabel?.text = peripheral.identifier
            
        } else {
            
            cell.textLabel?.text = peripheral.identifier
            cell.detailTextLabel?.text = ""
        }
    }
    
    // MARK: - UITableViewDataSource
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let cell = tableView.dequeueReusableCell(withIdentifier: "ServiceCell", for: indexPath)
        
        configure(cell: cell, at: indexPath)
        
        return cell
    }
}
