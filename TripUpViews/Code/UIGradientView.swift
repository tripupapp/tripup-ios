//
//  UIGradientView.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 11/10/2018.
//  Copyright © 2018 Vinoth Ramiah. All rights reserved.
//
//  https://gist.github.com/Banck/18a20901bcd6fb872a85b56ed71fcd12
//

import Foundation
import UIKit

@IBDesignable public class UIGradientView: UIView {
    @IBInspectable public var firstColor: UIColor = UIColor.clear.withAlphaComponent(0.0) {
        didSet {
            updateView()
        }
    }

    @IBInspectable public var secondColor: UIColor = UIColor.clear.withAlphaComponent(0.0) {
        didSet {
            updateView()
        }
    }

    @IBInspectable public var vertical: Bool = true {
        didSet {
            updateView()
        }
    }

    override public class var layerClass: AnyClass {
        get {
            return CAGradientLayer.self
        }
    }

    func updateView() {
        let layer = self.layer as! CAGradientLayer
        layer.colors = [firstColor, secondColor].map{ $0.cgColor }
        if (vertical) {
            layer.startPoint = CGPoint(x: 0.5, y: 0)
            layer.endPoint = CGPoint (x: 0.5, y: 1)
        } else {
            layer.startPoint = CGPoint(x: 0, y: 0.5)
            layer.endPoint = CGPoint (x: 1, y: 0.5)
        }
    }
}
