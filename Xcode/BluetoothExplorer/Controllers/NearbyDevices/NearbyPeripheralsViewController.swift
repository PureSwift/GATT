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
    
    fileprivate func configure(cell: NearbyPeripheralCell, scanData: ScanData) {
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
            
            guard let parameters = sender as? ([CentralManager.Service], ScanData) else {
                fatalError("sender should be convertible to Service")
            }
            
            peripheralServicesController.central = central
            peripheralServicesController.services = parameters.0
            peripheralServicesController.scanData = parameters.1
        }
    }
    
    // MARK: - Action
    
    @objc func handleRefresh(sender: Any) {
        scan()
    }
    
    fileprivate func scan() {
        self.refreshControl?.beginRefreshing()
        
        DispatchQueue.global(qos: .background).async { [unowned self] in
            
            let central = self.central
            central.waitForPoweredOn()
            
            self.results = central.scan(duration: 5)
            
            DispatchQueue.main.async {
                self.tableView.reloadData()
                self.refreshControl?.endRefreshing()
            }
        }
    }
    
    fileprivate func showError(_ error: Error) {
        DispatchQueue.main.async { self.showAlert(message: error.localizedDescription) }
    }
    
    fileprivate func connect(data: ScanData) -> Bool {
        do {
            try central.connect(to: data.peripheral)
            return true
        } catch {
            self.showError(error)
        }
        
        return false
    }
    
    fileprivate func discoverServices(data: ScanData) -> [CentralManager.Service]? {
        do {
            return try central.discoverServices(for: data.peripheral)
        } catch {
            self.showError(error)
        }
        
        return nil
    }
    
    fileprivate func showLoading() {
        DispatchQueue.main.async { HUD.show(.progress) }
    }
    
    fileprivate func hideLoading() {
        DispatchQueue.main.async { HUD.hide() }
    }
}

extension NearbyPeripheralsViewController {
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return results.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let data = results[indexPath.row]
        let identifier = String(describing: NearbyPeripheralCell.self)
        guard let cell = tableView.dequeueReusableCell(withIdentifier: identifier, for: indexPath) as? NearbyPeripheralCell else {
            fatalError("cell should be convertible to NearbyPeripheralCell")
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

            DispatchQueue.main.async {
                self.hideLoading()
                self.performSegue(withIdentifier: "showServices", sender: (services: services, data: data))
            }
            
        }
        
    }
    
}
