//
//  UITextField2.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 28/02/2018.
//  Copyright © 2018 Vinoth Ramiah. All rights reserved.
//

import Foundation
import UIKit

public class UITextField2: UITextField {
    private lazy var bottomLine: CALayer = {
           let bottomLine = CALayer()
           bottomLine.frame = CGRect(x: 0.0, y: self.frame.height - 1, width: self.frame.width, height: 1.0)
           bottomLine.isHidden = true
           return bottomLine
       }()

       @IBInspectable public var underline: Bool = false {
           didSet {
               if underline {
                   self.layer.addSublayer(bottomLine)
               } else {
                   bottomLine.removeFromSuperlayer()
               }
               render()
           }
       }

       @IBInspectable public var underlineColor: UIColor = .black {
           didSet {
               render()
           }
       }

       func render() {
           bottomLine.isHidden = !underline
           bottomLine.backgroundColor = underlineColor.cgColor
       }

       override public func layoutSublayers(of layer: CALayer) {
           super.layoutSublayers(of: layer)
           bottomLine.frame = CGRect(x: 0.0, y: self.bounds.height - 1, width: self.bounds.width, height: 1.0)
       }
}
