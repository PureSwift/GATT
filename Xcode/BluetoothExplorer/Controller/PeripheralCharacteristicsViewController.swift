//
//  PeripheralCharacteristicsViewController.swift
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

final class PeripheralCharacteristicsViewController: TableViewController {
    
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
        
        configureView()
        
        let isRefreshing = self.refreshControl?.isRefreshing ?? false
        let showActivity = isRefreshing == false
        
        performActivity(showActivity: showActivity, {
            try DeviceStore.shared.discoverCharacteristics(for: managedObject)
        }, completion: { (viewController, _) in
            viewController.endRefreshing()
        })
    }
    
    override func newFetchedResultController() -> NSFetchedResultsController<NSManagedObject> {
        
        guard let managedObject = self.service
            else { fatalError("View controller not configured") }
        
        // configure fetched results controller
        let predicate = NSPredicate(format: "%K == %@",
                                    #keyPath(CharacteristicManagedObject.service),
                                    managedObject)
        
        let sort = [NSSortDescriptor(key: #keyPath(CharacteristicManagedObject.uuid), ascending: true)]
        let context = DeviceStore.shared.managedObjectContext
        let fetchedResultsController = NSFetchedResultsController(CharacteristicManagedObject.self,
                                                                  delegate: self,
                                                                  predicate: predicate,
                                                                  sortDescriptors: sort,
                                                                  context: context)
        fetchedResultsController.fetchRequest.fetchBatchSize = 30
        
        return fetchedResultsController
    }
    
    private subscript (indexPath: IndexPath) -> CharacteristicManagedObject {
        
        guard let managedObject = self.fetchedResultsController?.object(at: indexPath) as? CharacteristicManagedObject
            else { fatalError("Invalid type") }
        
        return managedObject
    }
    
    private func configure(cell: UITableViewCell, at indexPath: IndexPath) {
        
        let managedObject = self[indexPath]
        
        let attributes = managedObject.attributesView
        
        if let name = attributes.uuid.name {
            
            cell.textLabel?.text = name
            cell.detailTextLabel?.text = attributes.uuid.rawValue
            
        } else {
            
            cell.textLabel?.text = attributes.uuid.rawValue
            cell.detailTextLabel?.text = ""
        }
    }
    
    // MARK: - UITableViewDataSource
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let cell = tableView.dequeueReusableCell(withIdentifier: "CharacteristicCell", for: indexPath)
        
        configure(cell: cell, at: indexPath)
        
        return cell
    }
    
    // MARK: - Segue
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        
        let identifier = segue.identifier ?? ""
        
        switch identifier {
            
        case "showPeripheralCharacteristic":
            
            let viewController = segue.destination as! PeripheralCharacteristicDetailViewController
            viewController.characteristic = self[tableView.indexPathForSelectedRow!]
            
        default:
            assertionFailure("Unknown segue \(segue)")
        }
    }
}

// MARK: - ActivityIndicatorViewController

extension PeripheralCharacteristicsViewController: ActivityIndicatorViewController {
    
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
