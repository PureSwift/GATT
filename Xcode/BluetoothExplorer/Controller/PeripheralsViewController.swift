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
    
    // MARK: - Properties
    
    let scanDuration: TimeInterval = 5.0
    
    private var scanStart = Date() {
        
        didSet { configureView() }
    }
    
    // MARK: - Loading

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // setup table view
        self.tableView.estimatedRowHeight = 96
        self.tableView.rowHeight = UITableViewAutomaticDimension
        
        // update table view
        self.configureView()
        self.reloadData()
    }
    
    // MARK: - Actions
    
    @IBAction func reloadData(_ sender: Any? = nil) {
        
        // don't scan if already scanning
        guard DeviceStore.shared.centralManager.isScanning == false,
            DeviceStore.shared.centralManager.state == .poweredOn
            else { return }
        
        let scanDuration = self.scanDuration
        
        // configure table view and update UI
        scanStart = Date()
        
        performActivity({ try DeviceStore.shared.scan(duration: scanDuration) },
                        completion: { (viewController, _) in viewController.refreshControl?.endRefreshing() })
    }
    
    // MARK: - Private Methods
    
    private func configureView() {
        
        // configure fetched results controller
        let predicate = NSPredicate(format: "%K > %@",
                                    #keyPath(PeripheralManagedObject.scanData.date),
                                    self.scanStart as NSDate)
        
        let sort = [NSSortDescriptor(key: #keyPath(PeripheralManagedObject.identifier), ascending: false)]
        let context = DeviceStore.shared.managedObjectContext
        self.fetchedResultsController = NSFetchedResultsController(PeripheralManagedObject.self,
                                                                   delegate: self,
                                                                   predicate: predicate,
                                                                   sortDescriptors: sort,
                                                                   context: context)
        
        self.fetchedResultsController.fetchRequest.fetchBatchSize = 30
        try! self.fetchedResultsController.performFetch()
        self.tableView.reloadData()
    }
    
    private subscript (indexPath: IndexPath) -> PeripheralManagedObject {
        
        guard let managedObject = self.fetchedResultsController.object(at: indexPath) as? PeripheralManagedObject
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
        
        let cell = tableView.dequeueReusableCell(withIdentifier: "PeripheralCell", for: indexPath)
        
        configure(cell: cell, at: indexPath)
        
        return cell
    }
}

extension PeripheralsViewController: ActivityIndicatorViewController { }
