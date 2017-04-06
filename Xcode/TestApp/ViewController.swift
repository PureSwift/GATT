//
//  ViewController.swift
//  TestApp
//
//  Created by Alsey Coleman Miller on 4/20/16.
//  Copyright © 2016 PureSwift. All rights reserved.
//

import UIKit
import GATT

final class ViewController: UIViewController {
    
    let central = CentralManager()

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        
        central.waitForPoweredOn()
        
        let duration = 5
        
        print("Scanning for \(duration) seconds")
        
        let scanResults = central.scan()
        
        print("Found \(scanResults.count) peripherals")
    }
}
