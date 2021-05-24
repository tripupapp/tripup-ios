//
//  UIViewControllerTransparent.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 09/09/2020.
//  Copyright © 2020 Vinoth Ramiah. All rights reserved.
//

import Foundation
import UIKit.UIViewController

protocol UIViewControllerTransparent: UIViewController {
    var transparent: Bool { get set }
    var navigationBarHidden: Bool { get set }
}
