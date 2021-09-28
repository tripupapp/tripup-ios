//
//  BadgeView.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 05/02/2020.
//  Copyright © 2020 Vinoth Ramiah. All rights reserved.
//

import Foundation
import UIKit.UIView

import BadgeSwift

protocol BadgeCounter: UIView {
    var color: UIColor { get set }
    var value: Int { get set }
}

class BadgeView: BadgeSwift {
    init(color: UIColor) {
        super.init(frame: .zero)
        setup(color: color)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup(color: UIColor = .red) {
        badgeColor = color
        textColor = .white
        isHidden = true
    }
}

extension BadgeView: BadgeCounter {
    var color: UIColor {
        get {
            return badgeColor
        }
        set {
            badgeColor = newValue
        }
    }

    var value: Int {
        get {
            if let text = text, let int = Int(text) {
                return int
            } else {
                return 0
            }
        }
        set {
            text = String(newValue)
            if newValue > 0 {
                isHidden = false
                sizeToFit()
            } else {
                isHidden = true
            }
        }
    }
}

//enum BadgeViewPosition {
//    case topLeft
//    case topRight
//}
//
//class BadgeView: UIView {
//    private let badgeView = BadgeSwift()
//    var position: BadgeViewPosition = .topLeft {
//        didSet {
//            set(position: position)
//        }
//    }
//
//    var text: String {
//        get {
//            return badgeView.text ?? ""
//        }
//        set {
//            if newValue == "0" {
//                badgeView.text = ""
//                badgeView.isHidden = true
//            } else {
//                badgeView.text = newValue
//                badgeView.isHidden = false
//            }
//        }
//    }
//
//    init(color: UIColor) {
//        super.init(frame: .zero)
//        self.addSubview(badgeView)
//
//        badgeView.textColor = .white
//        badgeView.badgeColor = color
//
//        badgeView.translatesAutoresizingMaskIntoConstraints = false
//        var constraints = [NSLayoutConstraint]()
//        // Center the badge vertically in its container
//        constraints.append(NSLayoutConstraint(
//          item: badgeView,
//          attribute: NSLayoutConstraint.Attribute.centerY,
//          relatedBy: NSLayoutConstraint.Relation.equal,
//          toItem: self,
//          attribute: NSLayoutConstraint.Attribute.centerY,
//          multiplier: 1, constant: 0)
//        )
//        // Center the badge horizontally in its container
//        constraints.append(NSLayoutConstraint(
//          item: badgeView,
//          attribute: NSLayoutConstraint.Attribute.centerX,
//          relatedBy: NSLayoutConstraint.Relation.equal,
//          toItem: self,
//          attribute: NSLayoutConstraint.Attribute.centerX,
//          multiplier: 1, constant: 0)
//        )
//        self.addConstraints(constraints)
//
//        self.text = "0"
//    }
//
//    required init?(coder: NSCoder) {
//        fatalError("init(coder:) has not been implemented")
//    }
//
//    private func set(position: BadgeViewPosition) {
//        guard let superview = self.superview else { preconditionFailure("BadgeView has not been added to a view yet, unable to set position") }
//        switch position {
//        case .topLeft:
//            self.frame.origin = CGPoint(x: 0, y: 0)
//        case .topRight:
//            self.frame.origin = CGPoint(x: superview.bounds.size.width - self.frame.width, y: 0)
//        }
//    }
//}
