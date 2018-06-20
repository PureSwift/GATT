//
//  ErrorAlert.swift
//  BluetoothExplorer
//
//  Created by Alsey Coleman Miller on 6/19/18.
//  Copyright © 2018 PureSwift. All rights reserved.
//

import Foundation
import UIKit

public extension UIViewController {
    
    /// Presents an error alert controller with the specified completion handlers.
    func showErrorAlert(_ localizedText: String,
                        okHandler: (() -> ())? = nil,
                        retryHandler: (()-> ())? = nil) {
        
        let alert = UIAlertController(title: NSLocalizedString("ErrorAlertError", comment: "Error"),
                                      message: localizedText,
                                      preferredStyle: .alert)
        
        alert.addAction(UIAlertAction(title: NSLocalizedString("ErrorAlertOK", comment: "OK"), style: UIAlertActionStyle.`default`, handler: { (UIAlertAction) in
            
            okHandler?()
            
            alert.presentingViewController?.dismiss(animated: true, completion: nil)
        }))
        
        // optionally add retry button
        
        if retryHandler != nil {
            
            alert.addAction(UIAlertAction(title: NSLocalizedString("ErrorAlertRetry", comment: "Retry"), style: UIAlertActionStyle.`default`, handler: { (UIAlertAction) in
                
                retryHandler!()
                
                alert.presentingViewController?.dismiss(animated: true, completion: nil)
            }))
        }
        
        self.present(alert, animated: true, completion: nil)
    }
}
