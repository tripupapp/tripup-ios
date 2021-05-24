//
//  Keyboard.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 25/04/2020.
//  Copyright © 2020 Vinoth Ramiah. All rights reserved.
//

import Foundation
import IQKeyboardManagerSwift

/*
 Keyboard class handles keyboard settings and resizing views when editing
 */
class Keyboard {
    static let shared = Keyboard()

    private init() {
        IQKeyboardManager.shared.shouldResignOnTouchOutside = true
    }

    var enabled: Bool {
        get {
            return IQKeyboardManager.shared.enable
        }
        set {
            IQKeyboardManager.shared.enable = newValue
        }
    }

    var keyboardDistanceFromTextField: CGFloat {
        return IQKeyboardManager.shared.keyboardDistanceFromTextField
    }

    func adjustKeyboardDistance(by distance: CGFloat) {
        IQKeyboardManager.shared.keyboardDistanceFromTextField = max(IQKeyboardManager.shared.keyboardDistanceFromTextField + distance, 0)
    }
}
