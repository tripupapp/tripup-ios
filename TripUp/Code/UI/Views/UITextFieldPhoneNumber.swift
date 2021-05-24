//
//  UITextFieldPhoneNumber.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 23/04/2020.
//  Copyright © 2020 Vinoth Ramiah. All rights reserved.
//

import Foundation
import UIKit

import PhoneNumberKit

@IBDesignable public class UITextFieldPhoneNumber: PhoneNumberTextField {
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

    public override func layoutSublayers(of layer: CALayer) {
        super.layoutSublayers(of: layer)
        bottomLine.frame = CGRect(x: 0.0, y: self.bounds.height - 1, width: self.bounds.width, height: 1.0)
    }
}
