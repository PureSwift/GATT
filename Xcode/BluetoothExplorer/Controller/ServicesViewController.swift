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
    
    public var peripheral: Peripheral!
    
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
        
        guard let identifier = self.peripheral?.identifier,
            let managedObject = try! PeripheralManagedObject.find(identifier, in: DeviceStore.shared.managedObjectContext)
            else { assertionFailure(); return }
        
        self.title = managedObject.scanData.advertisementData.localName ?? identifier.uuidString
    }
    
    func reloadData() {
        
        guard let peripheral = self.peripheral
            else { fatalError("View controller not configured") }
        
        configureView()
        
        performActivity({ try DeviceStore.shared.discoverServices(for: peripheral) },
                        completion: { (viewController, _) in viewController.endRefreshing() })
    }
    
    override func newFetchedResultController() -> NSFetchedResultsController<NSManagedObject> {
        
        guard let identifier = self.peripheral?.identifier
            else { fatalError("View controller not configured") }
        
        // configure fetched results controller
        let predicate = NSPredicate(format: "%K == %@",
                                    #keyPath(ServiceManagedObject.peripheral.identifier),
                                    identifier.uuidString as NSString)
        
        let sort = [NSSortDescriptor(key: #keyPath(ServiceManagedObject.uuid), ascending: true)]
        let context = DeviceStore.shared.managedObjectContext
        let fetchedResultsController = NSFetchedResultsController(ServiceManagedObject.self,
                                                                  delegate: self,
                                                                  predicate: predicate,
                                                                  sortDescriptors: sort,
                                                                  context: context)
        fetchedResultsController.fetchRequest.fetchBatchSize = 30
        
        return fetchedResultsController
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
