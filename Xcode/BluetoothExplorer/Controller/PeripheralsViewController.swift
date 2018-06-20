//
//  ViewController.swift
//  BluetoothExplorer
//
//  Created by Alsey Coleman Miller on 6/19/18.
//  Copyright © 2018 PureSwift. All rights reserved.
//

import Foundation
import UIKit
import CoreData
import Bluetooth
import GATT

final class PeripheralsViewController: TableViewController {
    
    // MARK: - Loading

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // setup table view
        self.tableView.estimatedRowHeight = 96
        self.tableView.rowHeight = UITableViewAutomaticDimension
        
        // configure fetched results controller
        let predicate = NSPredicate(format: "")
        let sort = [NSSortDescriptor(key: #keyPath(PeripheralManagedObject.identifier), ascending: false)]
        let context = DeviceStore.shared.managedObjectContext
        self.fetchedResultsController = NSFetchedResultsController(PeripheralManagedObject.self,
                                                                   delegate: self,
                                                                   predicate: predicate,
                                                                   sortDescriptors: sort,
                                                                   context: context)
        
        self.fetchedResultsController.fetchRequest.fetchBatchSize = 30
        try! self.fetchedResultsController.performFetch()
        
        self.reloadData()
    }
    
    // MARK: - Actions
    
    @IBAction func reloadData() {
        
        let timeInterval: TimeInterval = 5.0
        
        performActivity({ try DeviceStore.shared.scan(duration: timeInterval) },
                        completion: { (viewController, _) in viewController.refreshControl?.endRefreshing() })
    }
    
    // MARK: - Private Methods
    
    private subscript (indexPath: IndexPath) -> PeripheralManagedObject {
        
        let managedObject = self.fetchedResultsController.object(at: indexPath) as! PeripheralManagedObject
        
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
        
        let cell = tableView.dequeueReusableCell(withIdentifier: "PeripheralCell", for: indexPath)
        
        configure(cell: cell, at: indexPath)
        
        return cell
    }
}

extension PeripheralsViewController: ActivityIndicatorViewController { }
