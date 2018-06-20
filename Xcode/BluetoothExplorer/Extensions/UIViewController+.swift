//
//  UIViewController.swift
//  BluetoothExplorer
//
//  Created by Carlos Duclos on 4/8/18.
//  Copyright © 2018 PureSwift. All rights reserved.
//

import UIKit

extension UIViewController {
    
    @discardableResult
    func showAlert(message: String) -> UIAlertController {
        let alertController = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
        alertController.addAction(cancelAction)
        
        self.present(alertController, animated: true, completion: nil)
        return alertController
    }
    
}
