//
//  BatteryLevelCharacteristicViewController.swift
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

final class BatteryLevelCharacteristicViewController: UIViewController {
    
    // MARK: - IB Outlets
    
    @IBOutlet private(set) var textLabel: UILabel!
    
    @IBOutlet private(set) var slider: UISlider!
    
    // MARK: - Properties
    
    var value = GATTBatteryLevel(level: .min)
    
    var valueDidChange: ((GATTBatteryLevel) -> ())?
    
    // MARK: - Loading
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        configureView()
    }
    
    // MARK: - Actions
    
    @IBAction func sliderValueChanged(_ sender: UISlider) {
        
        guard let level = GATTBatteryPercentage(rawValue: UInt8(sender.value))
            else { assertionFailure("Invalid value \(sender.value)"); return }
        
        value = GATTBatteryLevel(level: level)
        updatePercentageText()
        valueDidChange?(value)
    }
    
    // MARK: - Methods
    
    func configureView() {
        
        guard isViewLoaded else { return }
        
        updatePercentageText()
        updateSlider()
    }
    
    func updateSlider() {
        
        slider.value = Float(value.level.rawValue)
    }
    
    func updatePercentageText() {
        
        textLabel.text = value.description
    }
}

// MARK: - CharacteristicViewController

extension BatteryLevelCharacteristicViewController: CharacteristicViewController {
    
    static func load(data: Data) -> BatteryLevelCharacteristicViewController {
        
        let storyboard = UIStoryboard(name: "BatteryLevelCharacteristic", bundle: .main)
        
        let viewController = storyboard.instantiateInitialViewController() as! BatteryLevelCharacteristicViewController
        
        if let newValue = CharacteristicValue(data: data) {
            
            viewController.value = newValue
            viewController.configureView()
        }
        
        return viewController
    }
}
