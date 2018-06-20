//
//  ActivityIndicatorViewController.swift
//  BluetoothExplorer
//
//  Created by Alsey Coleman Miller on 6/19/18.
//  Copyright © 2018 PureSwift. All rights reserved.
//

import Foundation
import UIKit

protocol ActivityIndicatorViewController: class {
    
    var view: UIView! { get }
    
    var navigationItem: UINavigationItem { get }
    
    var navigationController: UINavigationController? { get }
    
    func showActivity()
    
    func hideActivity(animated: Bool)
}

extension ActivityIndicatorViewController {
    
    func performActivity <T> (showProgressHUD: Bool = true,
                              _ asyncOperation: @escaping () throws -> T,
                              completion: ((Self, T) -> ())? = nil) {
        
        if showProgressHUD { self.showActivity() }
        
        async {
            
            do {
                
                let value = try asyncOperation()
                
                mainQueue { [weak self] in
                    
                    guard let controller = self
                        else { return }
                    
                    if showProgressHUD { controller.hideActivity(animated: true) }
                    
                    // success
                    completion?(controller, value)
                }
            }
                
            catch {
                
                mainQueue { [weak self] in
                    
                    guard let controller = self as? (UIViewController & ActivityIndicatorViewController)
                        else { return }
                    
                    if showProgressHUD { controller.hideActivity(animated: false) }
                    
                    // show error
                    
                    print("⚠️ Error: \(error)")
                    
                    controller.showErrorAlert(error.localizedDescription)
                }
            }
        }
    }
}
