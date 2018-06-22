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
    
    // MARK: - IB Outlets
    
    @IBOutlet private(set) var activityIndicatorBarButtonItem: UIBarButtonItem!
    
    // MARK: - Properties
    
    let scanDuration: TimeInterval = 5.0
    
    private var scanStart = Date() {
        
        didSet { performFetch() }
    }
    
    // MARK: - Loading
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        reloadData()
    }
    
    // MARK: - Actions
    
    @IBAction func pullToRefresh(_ sender: UIRefreshControl) {
        
        reloadData()
    }
    
    // MARK: - Methods
    
    func reloadData() {
        
        // configure table view and update UI
        scanStart = Date()
        
        // scan
        let scanDuration = self.scanDuration
        performActivity({ try DeviceStore.shared.scan(duration: scanDuration) })
    }
    
    override func newFetchedResultController() -> NSFetchedResultsController<NSManagedObject> {
        
        // configure fetched results controller
        let predicate = NSPredicate(format: "%K > %@",
                                    #keyPath(PeripheralManagedObject.scanData.date),
                                    self.scanStart as NSDate)
        
        let sort = [NSSortDescriptor(key: #keyPath(PeripheralManagedObject.identifier), ascending: false)]
        let context = DeviceStore.shared.managedObjectContext
        let fetchedResultsController = NSFetchedResultsController(PeripheralManagedObject.self,
                                                                  delegate: self,
                                                                  predicate: predicate,
                                                                  sortDescriptors: sort,
                                                                  context: context)
        fetchedResultsController.fetchRequest.fetchBatchSize = 30
        
        return fetchedResultsController
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
        
        let cell = tableView.dequeueReusableCell(withIdentifier: "PeripheralCell", for: indexPath)
        
        configure(cell: cell, at: indexPath)
        
        return cell
    }
    
    // MARK: - Segue
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        
        let identifier = segue.identifier ?? ""
        
        switch identifier {
            
        case "showPeripheralDetail":
            
            let viewController = segue.destination as! PeripheralServicesViewController
            viewController.peripheral = self[tableView.indexPathForSelectedRow!]
            
        default: assertionFailure("Unknown segue \(segue)")
        }
    }
}

// MARK: - ActivityIndicatorViewController

extension PeripheralsViewController: ActivityIndicatorViewController {
    
    func showActivity() {
        
        self.view.endEditing(true)
        
        let isRefreshing = self.refreshControl?.isRefreshing ?? false
        
        if isRefreshing == false {
            
            self.activityIndicatorBarButtonItem.customView?.alpha = 1.0
        }
        
        self.refreshControl?.isEnabled = false
    }
    
    func hideActivity(animated: Bool = true) {
        
        self.refreshControl?.isEnabled = true
        
        let isRefreshing = self.refreshControl?.isRefreshing ?? false
        
        if isRefreshing {
            
            self.endRefreshing()
            
        } else {
            
            let duration: TimeInterval = animated ? 0.5 : 0.0
            
            UIView.animate(withDuration: duration) { [weak self] in
                
                self?.activityIndicatorBarButtonItem.customView?.alpha = 0.0
            }
        }
    }
}
