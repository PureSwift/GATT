//
//  ActivityIndicatorViewController.swift
//  BluetoothExplorer
//
//  Created by Alsey Coleman Miller on 6/19/18.
//  Copyright © 2018 PureSwift. All rights reserved.
//

import Foundation
import UIKit
//import JGProgressHUD

protocol ActivityIndicatorViewController: class {
    
    var view: UIView! { get }
    
    var navigationItem: UINavigationItem { get }
    
    var navigationController: UINavigationController? { get }
    
    //var progressHUD: JGProgressHUD { get }
    
    func showProgressHUD()
    
    func dismissProgressHUD(animated: Bool)
}

extension ActivityIndicatorViewController {
    
    func showProgressHUD() {
        
        self.view.isUserInteractionEnabled = false
        self.view.endEditing(true)
        
        //progressHUD.show(in: self.navigationController?.view ?? self.view)
    }
    
    func dismissProgressHUD(animated: Bool = true) {
        
        self.view.isUserInteractionEnabled = true
        
        //progressHUD.dismiss(animated: animated)
    }
}

extension ActivityIndicatorViewController {
    
    func performActivity <T> (showProgressHUD: Bool = true,
                              _ asyncOperation: @escaping () throws -> T,
                              completion: ((Self, T) -> ())? = nil) {
        
        if showProgressHUD { self.showProgressHUD() }
        
        async {
            
            do {
                
                let value = try asyncOperation()
                
                mainQueue { [weak self] in
                    
                    guard let controller = self
                        else { return }
                    
                    if showProgressHUD { controller.dismissProgressHUD() }
                    
                    // success
                    completion?(controller, value)
                }
            }
                
            catch {
                
                mainQueue { [weak self] in
                    
                    guard let controller = self as? (UIViewController & ActivityIndicatorViewController)
                        else { return }
                    
                    if showProgressHUD { controller.dismissProgressHUD(animated: false) }
                    
                    // show error
                    
                    print("⚠️ Error: \(error)")
                    
                    controller.showErrorAlert(error.localizedDescription)
                }
            }
        }
    }
}
