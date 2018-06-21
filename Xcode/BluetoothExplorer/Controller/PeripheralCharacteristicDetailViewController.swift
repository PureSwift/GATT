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
    
    var characteristic: CharacteristicManagedObject! {
        
        didSet { configureView() }
    }
    
    private var dataSource = [Section]()
    
    private lazy var cellCache: CellCache = CellCache(tableView: tableView)
    
    private var _editViewController: UIViewController?
    
    // MARK: - Loading
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        configureView()
    }
    
    // MARK: - Methods
    
    private func configureView() {
        
        guard isViewLoaded else { return }
        
        guard let managedObject = self.characteristic
            else { fatalError("View controller not configured") }
        
        let characteristic = managedObject.attributesView
        
        self.title = characteristic.uuid.rawValue
        
        self.dataSource = []
        self.dataSource.reserveCapacity(2)
        
        // value cell
        var valueSection = Section(title: "Value", items: [cellCache.hexadecimalCell])
        configureHexadecimalTextField()
        
        // editor cell
        self._editViewController = nil // reset cache
        if let name = characteristic.uuid.name, editViewController != nil {
            
            let editCell = cellCache.editCell
            
            editCell.textLabel?.text = "Edit " + name
            
            valueSection.items.append(editCell)
        }
        
        self.dataSource.append(valueSection)
        
        // properties
        var propertiesSection = Section(title: "Properties", items: [])
        
        if characteristic.properties.contains(.read) {
            
            propertiesSection.items.append(cellCache.readValueCell)
        }
        
        if characteristic.properties.contains(.write) {
            
            propertiesSection.items.append(cellCache.writeValueCell)
        }
        
        if characteristic.properties.contains(.writeWithoutResponse) {
            
            propertiesSection.items.append(cellCache.writeWithoutResponseCell)
        }
        
        if propertiesSection.items.isEmpty == false {
            
            self.dataSource.append(propertiesSection)
        }
        
        tableView.reloadData()
    }
    
    private func configureHexadecimalTextField() {
        
        cellCache.hexadecimalCell.textField.text = characteristic.value?.toHexadecimal() ?? ""
    }
    
    private var editViewController: UIViewController? {
        
        if _editViewController == nil {
            
            let characteristic = self.characteristic.attributesView
            
            let data = characteristic.value ?? Data()
            
            let viewController: UIViewController?
            
            switch characteristic.uuid {
                
            case BatteryLevelCharacteristicViewController.uuid:
                
                viewController = BatteryLevelCharacteristicViewController.load(data: data)
                
            default:
                
                viewController = nil
            }
            
            _editViewController = viewController
        }
        
        return _editViewController
    }
    
    // MARK: - UITableViewDataSource
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        
        return dataSource.count
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        
        return dataSource[section].items.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let cell = dataSource[indexPath.section].items[indexPath.row]
        
        return cell
    }
    
    // MARK: - UITableViewDelegate
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        
        let section = self.dataSource[section]
        
        return section.title
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        
        let section = self.dataSource[indexPath.section]
        
        let cell = section.items[indexPath.row]
        
        guard let cellIdentifier = Cell(rawValue: cell.reuseIdentifier ?? "")
            else { assertionFailure("Invalid cell"); return }
        
        switch cellIdentifier {
            
        case .hexadecimal:
            break
            
        case .edit:
            
            if let editViewController = self.editViewController {
                
                show(editViewController, sender: self)
            }
            
        case .read:
            break
            
        case .write:
            break
            
        case .writeWithoutResponse:
            break
        }
    }
}

extension PeripheralCharacteristicDetailViewController: UITextFieldDelegate {
    
    func textFieldDidBeginEditing(_ textField: UITextField) {
        
        
    }
}

// MARK: - Supporting Types

private extension PeripheralCharacteristicDetailViewController {
    
    enum Cell: String {
        
        case hexadecimal = "HexadecimalValueTableViewCell"
        
        case edit = "EditCell"
        
        case read = "ReadValueCell"
        
        case write = "WriteValueCell"
        
        case writeWithoutResponse = "WriteWithoutResponseCell"
    }
    
    struct Section {
        
        let title: String?
        
        var items: [UITableViewCell]
    }
    
    final class CellCache {
        
        init(tableView: UITableView) {
            
            self.tableView = tableView
        }
        
        private(set) weak var tableView: UITableView!
        
        private func dequeueReusableCell <T: UITableViewCell> (_ cell: Cell) -> T {
            
            return tableView.dequeueReusableCell(withIdentifier: cell.rawValue) as! T
        }
        
        lazy var hexadecimalCell: HexadecimalValueTableViewCell = self.dequeueReusableCell(.hexadecimal)
        
        lazy var editCell: UITableViewCell = self.dequeueReusableCell(.edit)
        
        lazy var readValueCell: UITableViewCell = self.dequeueReusableCell(.read)
        
        lazy var writeValueCell: UITableViewCell = self.dequeueReusableCell(.write)
        
        lazy var writeWithoutResponseCell: UITableViewCell = self.dequeueReusableCell(.writeWithoutResponse)
    }
}

final class HexadecimalValueTableViewCell: UITableViewCell {
    
    @IBOutlet private(set) var textField: UITextField!
}
