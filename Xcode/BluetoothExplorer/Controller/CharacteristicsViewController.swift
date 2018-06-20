//
//  CharacteristicsViewController.swift
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

final class CharacteristicsViewController: TableViewController {
    
    // MARK: - IB Outlets
    
    @IBOutlet private(set) var activityIndicatorBarButtonItem: UIBarButtonItem!
    
    // MARK: - Properties
    
    public var service: ServiceManagedObject!
    
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
        
        guard let managedObject = self.service
            else { fatalError("View controller not configured") }
        
        let service = CentralManager.Service(managedObject: managedObject)
        
        self.title = service.uuid.name ?? service.uuid.rawValue
    }
    
    func reloadData() {
        
        guard let managedObject = self.service
            else { fatalError("View controller not configured") }
        
        let service = CentralManager.Service(managedObject: managedObject)
        let peripheral = Peripheral(identifier: PeerIdentifier(rawValue: managedObject.peripheral.identifier)!)
        
        configureView()
        
        let isRefreshing = self.refreshControl?.isRefreshing ?? false
        let showActivity = isRefreshing == false
        
        performActivity(showActivity: showActivity, {
            try DeviceStore.shared.discoverCharacteristics(for: service.uuid, peripheral: peripheral)
        }, completion: {
            (viewController, _) in
            viewController.endRefreshing()
        })
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
        
        let managedObject = self[indexPath]
        
        let service = CentralManager.Service(managedObject: managedObject)
        
        if let name = service.uuid.name {
            
            cell.textLabel?.text = name
            cell.detailTextLabel?.text = service.uuid.rawValue
            
        } else {
            
            cell.textLabel?.text = service.uuid.rawValue
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

// MARK: - ActivityIndicatorViewController

extension CharacteristicsViewController: ActivityIndicatorViewController {
    
    func showActivity() {
        
        self.view.endEditing(true)
        
        self.activityIndicatorBarButtonItem.customView?.alpha = 1.0
    }
    
    func hideActivity(animated: Bool = true) {
        
        let duration: TimeInterval = animated ? 0.5 : 0.0
        
        UIView.animate(withDuration: duration) { [weak self] in
            
            self?.activityIndicatorBarButtonItem.customView?.alpha = 0.0
        }
    }
}

// MARK: - Supporting Types

extension CharacteristicsViewController {
    
    enum Identifier {
        
        case peripheral(Peripheral, service: BluetoothUUID)
        case server(String, service: BluetoothUUID)
    }
}
