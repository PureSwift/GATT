//
//  TableViewController.swift
//  BluetoothExplorer
//
//  Created by Alsey Coleman Miller on 6/19/18.
//  Copyright © 2018 PureSwift. All rights reserved.
//

import Foundation
import UIKit
import CoreData

/// Base table view controller 
class TableViewController: UITableViewController, NSFetchedResultsControllerDelegate {
    
    // MARK: - Properties
    
    final private(set) var fetchedResultsController: NSFetchedResultsController<NSManagedObject>?
    
    // MARK: - Loading
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // setup table view
        self.tableView.estimatedRowHeight = UITableViewAutomaticDimension
        self.tableView.rowHeight = UITableViewAutomaticDimension
        
        // update table view
        self.configureView()
        self.reloadData()
    }
    
    // MARK: - Methods
    
    /// Reset `NSFetchedResultsController`.
    func reloadData() {
        
        fetchedResultsController = nil
        tableView.reloadData()
        configureView()
        fetchedResultsController = newFetchedResultController()
        
        do { try fetchedResultsController?.performFetch() }
        catch { assertionFailure("\(error)") }
        tableView.reloadData()
    }
    
    /// Update UI.
    func configureView() {
        
        
    }
    
    /// Create a new `NSFetchedResultsController` instance.
    func newFetchedResultController() -> NSFetchedResultsController<NSManagedObject> {
        
        fatalError("\(newFetchedResultController) - Subclasses must override this implementation")
    }
    
    #if os(iOS)
    @IBAction func pullToRefresh(_ sender: UIRefreshControl) {
        
        reloadData()
        endRefreshing()
    }
    #endif
    
    final func endRefreshing() {
        
        if let refreshControl = self.refreshControl,
            refreshControl.isRefreshing == true {
            
            refreshControl.endRefreshing()
        }
    }
    
    // MARK: - UITableViewDataSource
    
    final override func numberOfSections(in tableView: UITableView) -> Int {
        
        return self.fetchedResultsController?.sections?.count ?? 0
    }
    
    final override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        
        return self.fetchedResultsController?.sections?[section].numberOfObjects ?? 0
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        
        guard let sections = self.fetchedResultsController?.sections
            else { return nil }
        
        return sections[section].name
    }
    
    #if os(iOS)
    override func tableView(_ tableView: UITableView, sectionForSectionIndexTitle title: String, at index: Int) -> Int {
        
        return self.fetchedResultsController?.section(forSectionIndexTitle: title, at: index)
            ?? super.tableView(tableView, sectionForSectionIndexTitle: title, at: index)
    }
    #endif
    
    // MARK: - NSFetchedResultsControllerDelegate
    
    final func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        
        self.tableView.beginUpdates()
    }
    
    final func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        
        self.tableView.endUpdates()
    }
    
    final func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
        
        switch type {
        case .insert:
            
            if let insertIndexPath = newIndexPath {
                self.tableView.insertRows(at: [insertIndexPath], with: .fade)
            }
        case .delete:
            
            if let deleteIndexPath = indexPath {
                self.tableView.deleteRows(at: [deleteIndexPath], with: .fade)
            }
        case .update:
            if let updateIndexPath = indexPath,
                let _ = self.tableView.cellForRow(at: updateIndexPath) {
                
                self.tableView.reloadRows(at: [updateIndexPath], with: .none)
            }
        case .move:
            
            if let deleteIndexPath = indexPath {
                self.tableView.deleteRows(at: [deleteIndexPath], with: .fade)
            }
            
            if let insertIndexPath = newIndexPath {
                self.tableView.insertRows(at: [insertIndexPath], with: .fade)
            }
        }
    }
    
    final func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange sectionInfo: NSFetchedResultsSectionInfo, atSectionIndex sectionIndex: Int, for type: NSFetchedResultsChangeType) {
        
        switch type {
            
        case .insert:
            
            self.tableView.insertSections(IndexSet(integer: sectionIndex), with: .automatic)
            
        case .delete:
            
            self.tableView.deleteSections(IndexSet(integer: sectionIndex), with: .automatic)
            
        default: break
        }
    }
}
