//
//  UIStoryBoardSegueWithCompletion.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 10/11/2020.
//  Copyright © 2020 Vinoth Ramiah. All rights reserved.
//

import Foundation
import UIKit.UIStoryboardSegue

class UIStoryboardSegueWithCompletion: UIStoryboardSegue {
    var completion: (() -> Void)?

    override func perform() {
        super.perform()
        completion?()
    }
}
