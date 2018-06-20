//
//  AdaptiveNavigation.swift
//  BluetoothExplorer
//
//  Created by Alsey Coleman Miller on 6/19/18.
//  Copyright © 2018 PureSwift. All rights reserved.
//

import Foundation
import UIKit

internal extension UIViewController {
    
    func showAdaptiveDetail(_ viewController: UIViewController, sender: Any? = nil) {
        
        // iPhone
        if splitViewController?.viewControllers.count == 1 {
            
            self.show(viewController, sender: sender)
        }
            // iPad
        else {
            
            let navigationController = UINavigationController(rootViewController: viewController)
            
            self.showDetailViewController(navigationController, sender: sender)
        }
    }
}
