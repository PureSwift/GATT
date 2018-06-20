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
    
    func configureView() {
        
        guard isViewLoaded else { return }
        
        self.title = peripheral.scanData.advertisementData.localName ?? peripheral.identifier
    }
    
    func reloadData() {
        
        configureView()
        
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
        
        // create FRC
        super.reloadData()
        
        // scan
        let scanDuration = self.scanDuration
        performActivity({ try DeviceStore.shared.scan(duration: scanDuration) },
                        completion: { (viewController, _) in viewController.endRefreshing() })
    }
    
    private subscript (indexPath: IndexPath) -> ServiceManagedObject {
        
        guard let managedObject = self.fetchedResultsController?.object(at: indexPath) as? ServiceManagedObject
            else { fatalError("Invalid type") }
        
        return managedObject
    }
    
    private func configure(cell: UITableViewCell, at indexPath: IndexPath) {
        
        let service = self[indexPath]
        
        cell.textLabel?.text = service.uuid
    }
    
    // MARK: - UITableViewDataSource
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let cell = tableView.dequeueReusableCell(withIdentifier: "ServiceCell", for: indexPath)
        
        configure(cell: cell, at: indexPath)
        
        return cell
    }
}

// MARK: - ActivityIndicatorViewController

extension ServicesViewController: ActivityIndicatorViewController { }
