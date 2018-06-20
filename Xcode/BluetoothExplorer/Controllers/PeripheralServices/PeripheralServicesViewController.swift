//
//  PeripheralServicesViewController.swift
//  BluetoothExplorer
//
//  Created by Carlos Duclos on 4/8/18.
//  Copyright © 2018 PureSwift. All rights reserved.
//

import Foundation

import UIKit
import GATT
import Bluetooth

class PeripheralServicesViewController: UITableViewController {
    
    struct Section {
        var title: String
        var items: [Item]
    }
    
    struct Item {
        var title: String
        var subtitle: String
    }
    
    // MARK: - Properties
    
    weak var central: CentralManager?
    var scanData: ScanData?
    var groups: [BluetoothUUID: [CentralManager.Characteristic]] = [:]
    var sections: [Section] = []
    
    // MARK: - Life cycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }
    
    // MARK: - Configuration
    
    private func setupUI() {
        tableView.rowHeight = UITableViewAutomaticDimension
        tableView.estimatedRowHeight = UITableViewAutomaticDimension
        
        if let data = scanData?.advertisementData.manufacturerData {
            let string = String(data: data, encoding: .utf8)
            let infoSection = Section(title: "Device Information", items: [Item(title: "Manufacturer", subtitle: string ?? "Empty")])
            sections.append(infoSection)
        }
        
        let serviceSections = groups.map { group -> Section in
            
            let characteristicItems = group.value.map { characteristic in
                Item(title: characteristic.uuid.rawValue, subtitle: characteristic.formattedProperties)
            }
            
            return Section(title: group.key.rawValue, items: characteristicItems)
        }
        
        sections.append(contentsOf: serviceSections)
    }
    
    fileprivate func configure(cell: DetailCell, item: Item) {
        cell.titleLabel.text = item.title
        cell.subtitleLabel.text = item.subtitle
    }
}

extension PeripheralServicesViewController {
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return sections.count
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return sections[section].title
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return sections[section].items.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let item = sections[indexPath.section].items[indexPath.row]
        let identifier = String(describing: DetailCell.self)
        guard let cell = tableView.dequeueReusableCell(withIdentifier: identifier, for: indexPath) as? DetailCell else {
            fatalError("cell should be convertible to DetailCell")
        }
        configure(cell: cell, item: item)
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
    }
    
}
