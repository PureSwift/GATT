//
//  UIAlertAction.swift
//  BluetoothExplorer
//
//  Created by Alsey Coleman Miller on 6/19/18.
//  Copyright © 2018 PureSwift. All rights reserved.
//

import Foundation
import UIKit

extension UIAlertController {
    
    enum DefaultAction {
        
        case cancel
    }
    
    func addAction(_ action: DefaultAction) {
        
        let alertAction: UIAlertAction
        
        switch action {
            
        case .cancel:
            
            alertAction = UIAlertAction(title: "cancel", style: .cancel) { [unowned self] _ in
                
                self.dismiss(animated: true, completion: nil)
            }
        }
        
        addAction(alertAction)
    }
}
