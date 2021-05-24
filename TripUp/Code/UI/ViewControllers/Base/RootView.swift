//
//  RootView.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 17/03/2018.
//  Copyright © 2018 Vinoth Ramiah. All rights reserved.
//

import Foundation
import UIKit

class RootView: UINavigationController {}

extension RootView: UINavigationControllerDelegate {
    func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {
//        if viewController is GalleryVC {
//            navigationBar.titleTextAttributes = [NSAttributedString.Key.font: UIFont(name: "Audiowide-Regular", size: 18.5)!]
//        } else {
//            navigationBar.titleTextAttributes = [NSAttributedString.Key.font: UIFont.systemFont(ofSize: 17.0, weight: .bold)]
//        }
    }
}
