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
    
    var value: Data? {
        
        didSet { configureHexadecimalTextField() }
    }
    
    private var dataSource = [Section]()
    
    private lazy var cellCache: CellCache = CellCache(tableView: tableView)
    
    // MARK: - Loading
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        hideActivity(animated: false)
        cellCache.hexadecimalCell.textField.delegate = self
        configureView()
        
        // automatically read value if supported
        if self.characteristic.attributesView.properties.contains(.read) {
            
            readValue()
        }
    }
    
    // MARK: - Methods
    
    private func configureView() {
        
        guard isViewLoaded else { return }
        
        guard let managedObject = self.characteristic
            else { fatalError("View controller not configured") }
        
        let characteristic = managedObject.attributesView
        
        self.title = characteristic.uuid.name ?? characteristic.uuid.rawValue
        
        let canWrite = characteristic.properties.contains(.write)
                    || characteristic.properties.contains(.writeWithoutResponse)
        
        self.dataSource = []
        self.dataSource.reserveCapacity(2)
        
        // value cell
        var valueSection = Section(title: "Value", items: [cellCache.hexadecimalCell])
        self.loadValue()
        
        // editor cell
        if supportedCharacteristicViewControllers.contains(characteristic.uuid) {
            
            let name = characteristic.uuid.name ?? characteristic.uuid.rawValue
            
            let editCell = cellCache.editCell
            
            let editText: String
            
            if canWrite {
                
                editText = "Edit " + name
                
            } else {
                
                editText = "View " + name
            }
            
            editCell.textLabel?.text = editText
            
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
    
    private func loadValue() {
        
        self.value = self.characteristic.value
    }
    
    private func configureHexadecimalTextField() {
        
        cellCache.hexadecimalCell.textField.text = self.value?.toHexadecimal() ?? ""
    }
    
    private func editViewController() -> UIViewController? {
        
        let characteristic = self.characteristic.attributesView
                
        let canWrite = characteristic.properties.contains(.write)
            || characteristic.properties.contains(.writeWithoutResponse)
        
        func load <T: CharacteristicViewController & UIViewController> (_ type: T.Type) -> T {
            
            let viewController = T.fromStoryboard()
            
            if let data = self.value, let value = T.CharacteristicValue(data: data) {
                
                viewController.value = value
            }
            
            if canWrite {
                
                viewController.valueDidChange = { [weak self] in self?.value = $0.data }
            }
            
            return viewController
        }
        
        let viewController: UIViewController?
        
        switch characteristic.uuid {
            
        case BatteryLevelCharacteristicViewController.uuid:
            viewController = load(BatteryLevelCharacteristicViewController.self)
            
        default:
            viewController = nil
        }
        
        return viewController
    }
    
    private func edit() {
        
        guard let viewController = editViewController()
            else { assertionFailure("Could not initialize editor view controller"); return }
        
        show(viewController, sender: self)
    }

    private func readValue() {
        
        performActivity({
            try DeviceStore.shared.readValue(for: self.characteristic)
        }, completion: { (viewController, _) in
            viewController.loadValue()
        })
    }
    
    private func writeValue(withResponse: Bool = true) {
        
        let data = self.value ?? Data()
        
        performActivity({
            try DeviceStore.shared.writeValue(data, withResponse: withResponse, for: self.characteristic)
        })
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
        
        defer { tableView.deselectRow(at: indexPath, animated: true) }
        
        let section = self.dataSource[indexPath.section]
        
        let cell = section.items[indexPath.row]
        
        guard let cellIdentifier = Cell(rawValue: cell.reuseIdentifier ?? "")
            else { assertionFailure("Invalid cell"); return }
        
        switch cellIdentifier {
            
        case .hexadecimal:
            break
            
        case .edit:
            edit()
            
        case .read:
            readValue()
            
        case .write:
            writeValue()
            
        case .writeWithoutResponse:
            writeValue(withResponse: false)
        }
    }
}

extension PeripheralCharacteristicDetailViewController: UITextFieldDelegate {
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        
        textField.resignFirstResponder()
        return false
    }
    
    func textFieldDidBeginEditing(_ textField: UITextField) {
        
        
    }
}

extension PeripheralCharacteristicDetailViewController: ActivityIndicatorViewController {
    
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
