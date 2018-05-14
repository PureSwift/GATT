//
//  NearbyPeripheralsViewController.swift
//  TestApp
//
//  Created by Carlos Duclos on 4/8/18.
//  Copyright © 2018 PureSwift. All rights reserved.
//

import UIKit
import GATT
import Bluetooth
import PKHUD

final class NearbyPeripheralsViewController: UITableViewController {
    
    // MARK: - Properties
    
    let central = CentralManager()
    var results: [ScanData] = []
    var loadingController: UIAlertController?
    
    // MARK: - Life cycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        scan()
    }
    
    // MARK: - Configuration
    
    private func setupUI() {
        tableView.rowHeight = UITableViewAutomaticDimension
        tableView.estimatedRowHeight = UITableViewAutomaticDimension
        
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(handleRefresh(sender:)), for: .valueChanged)
        refreshControl.tintColor = UIColor(red: 0.25, green: 0.72, blue: 0.85, alpha: 1.0)
        refreshControl.attributedTitle = NSAttributedString(string: "Scanning devices ...")
        self.refreshControl = refreshControl
    }
    
    private func configure(cell: DetailCell, scanData: ScanData) {
        let peripheralName = scanData.advertisementData.localName
        cell.titleLabel.text = peripheralName != nil ? peripheralName : "Unnamed"
        
        let services = scanData.advertisementData.serviceUUIDs.count
        cell.subtitleLabel.text = services > 0 ? "\(services) services" : "No services"
        cell.accessoryType = .disclosureIndicator
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "showServices" {
            guard let peripheralServicesController = segue.destination as? PeripheralServicesViewController else {
                fatalError("destination should be convertible to PeripheralServicesViewController")
            }
            
            guard let parameters = sender as? ([BluetoothUUID: [CentralManager.Characteristic]], ScanData) else {
                fatalError("sender should be convertible to [BluetoothUUID: CentralManager.Characteristic]")
            }
            
            peripheralServicesController.central = central
            peripheralServicesController.groups = parameters.0
            peripheralServicesController.scanData = parameters.1
        }
    }
    
    // MARK: - Action
    
    @objc func handleRefresh(sender: Any) {
        scan()
    }
    
    // MARK: - Private
    
    private func scan() {
        self.refreshControl?.beginRefreshing()
        
        DispatchQueue.global(qos: .background).async { [unowned self] in
            
            self.central.disconnectAll()
            self.central.waitForPoweredOn()
            
            self.results = self.central.scan(duration: 5)
            
            DispatchQueue.main.async {
                self.tableView.reloadData()
                self.refreshControl?.endRefreshing()
            }
        }
    }
    
    private func showError(_ error: Error) {
        DispatchQueue.main.async { self.showAlert(message: error.localizedDescription) }
    }
    
    private func connect(data: ScanData) -> Bool {
        do {
            try central.connect(to: data.peripheral)
            return true
        } catch {
            self.showError(error)
        }
        
        return false
    }
    
    private func discoverServices(data: ScanData) -> [CentralManager.Service]? {
        do {
            return try central.discoverServices(for: data.peripheral)
        } catch {
            self.showError(error)
        }
        
        return nil
    }
    
    private func showLoading() {
        DispatchQueue.main.async { HUD.show(.progress) }
    }
    
    private func hideLoading() {
        DispatchQueue.main.async { HUD.hide() }
    }
}

extension NearbyPeripheralsViewController {
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return results.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let data = results[indexPath.row]
        let identifier = String(describing: DetailCell.self)
        guard let cell = tableView.dequeueReusableCell(withIdentifier: identifier, for: indexPath) as? DetailCell else {
            fatalError("cell should be convertible to DetailCell")
        }
        
        configure(cell: cell, scanData: data)
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let data = results[indexPath.row]
        
        showLoading()
        DispatchQueue.global(qos: .background).async { [unowned self] in
            
            guard self.connect(data: data) else { self.hideLoading(); return }
            
            guard let services = self.discoverServices(data: data) else { self.hideLoading(); return }
            
            var groups: [BluetoothUUID: [CentralManager.Characteristic]] = [:]
            
            services.forEach { service in
                print("service", service)
                do {
                    let characteristics = try self.central.discoverCharacteristics(for: service.uuid, peripheral: data.peripheral)
                    groups[service.uuid] = characteristics
                    
                    characteristics.forEach({ characteristic in
                        print("characteristic", characteristic)
                    })
                } catch {
                    print(error)
                }
            }
            
            DispatchQueue.main.async {
                self.hideLoading()
                self.performSegue(withIdentifier: "showServices", sender: (groups: groups, data: data))
            }
        }
    }
    
}
