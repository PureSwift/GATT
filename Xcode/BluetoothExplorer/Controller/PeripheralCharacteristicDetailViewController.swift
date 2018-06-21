//
//  PeripheralCharacteristicDetailViewController.swift
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

final class PeripheralCharacteristicDetailViewController: UITableViewController {
    
    // MARK: - IB Outlets
    
    @IBOutlet private(set) var activityIndicatorBarButtonItem: UIBarButtonItem!
    
    // MARK: - Properties
    
    var characteristic: CharacteristicManagedObject!
    
    private var cells = [[UITableViewCell]]()
    
    private lazy var hexadecimalCell: HexadecimalValueTableViewCell = self.dequeueReusableCell(.hexadecimal)
    
    private lazy var editCell: UITableViewCell = self.dequeueReusableCell(.edit)
    
    // MARK: - Loading
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        configureView()
    }
    
    // MARK: - Actions
    
    @IBAction func readValue(_ sender: Any? = nil) {
        
        
    }
    
    @IBAction func writeValue(_ sender: Any? = nil) {
        
        
    }
    
    // MARK: - Methods
    
    private func configureView() {
        
        guard isViewLoaded else { return }
        
        guard let managedObject = self.characteristic
            else { fatalError("View controller not configured") }
        
        let characteristic = managedObject.attributesView
        
        self.title = characteristic.uuid.name ?? characteristic.uuid.rawValue
        
        self.cells = [[hexadecimalCell]]
        
        if editViewController() != nil {
            
            
        }
    }
    
    private func dequeueReusableCell <T: UITableViewCell> (_ cell: Cell) -> T {
        
        return tableView.dequeueReusableCell(withIdentifier: cell.rawValue) as! T
    }
    
    private func editViewController() -> UIViewController? {
        
        let characteristic = self.characteristic.attributesView
        
        let data = characteristic.value ?? Data()
        
        let viewController: UIViewController?
        
        switch characteristic.uuid {
            
        case BatteryLevelCharacteristicViewController.uuid:
            
            viewController = BatteryLevelCharacteristicViewController.load(data: data)
            
        default:
            
            viewController = nil
        }
        
        return viewController
    }
    
    // MARK: - UITableViewDataSource
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        
        return cells.count
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        
        return cells[section].count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        return cells[indexPath.section][indexPath.row]
    }
    
    // MARK: - UITableViewDelegate
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        
        let cell = cells[indexPath.section][indexPath.row]
        
        guard let cellIdentifier = Cell(rawValue: cell.reuseIdentifier ?? "")
            else { assertionFailure("Invalid cell"); return }
        
        switch cellIdentifier {
            
        case .hexadecimal:
            break
            
        case .edit:
            
            if let editViewController = self.editViewController() {
                
                show(editViewController, sender: self)
            }
        }
    }
}

// MARK: - Supporting Types

private extension PeripheralCharacteristicDetailViewController {
    
    enum Cell: String {
        
        case hexadecimal = "HexadecimalValueTableViewCell"
        
        case edit = "EditCell"
    }
}

final class HexadecimalValueTableViewCell: UITableViewCell {
    
    @IBOutlet private(set) var textField: UITextField!
}
