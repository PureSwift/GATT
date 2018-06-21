//
//  Button.swift
//  BluetoothExplorer
//
//  Created by Alsey Coleman Miller on 6/20/18.
//  Copyright © 2018 PureSwift. All rights reserved.
//

import Foundation
import UIKit

///
@IBDesignable final class CustomButton: UIButton {
    
    // MARK: - Properties
    
    @IBInspectable
    public var cornerRadius: CGFloat {
        
        get { return layer.cornerRadius }
        
        set { layer.cornerRadius = newValue }
    }
    
    @IBInspectable
    public var borderWidth: CGFloat {
        
        get { return layer.borderWidth }
        
        set { layer.borderWidth = newValue }
    }
    
    @IBInspectable
    public var borderColor: UIColor {
        
        get { return UIColor(cgColor: layer.borderColor ?? UIColor.clear.cgColor) }
        
        set { layer.borderColor = newValue.cgColor }
    }
    
    // MARK: - Loading
    
    override open func awakeFromNib() {
        super.awakeFromNib()
        
        
    }
}
