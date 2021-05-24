//
//  MainVC.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 19/08/2020.
//  Copyright © 2020 Vinoth Ramiah. All rights reserved.
//

import Foundation
import UIKit

class MainVC: UITabBarController {
    func initialise(dependencyInjector: DependencyInjector) {
        guard let viewControllers = viewControllers else { return }
        for viewController in viewControllers {
            let navigationController = viewController as? UINavigationController
            switch navigationController?.topViewController {
            case let libraryVC as LibraryVC:
                dependencyInjector.initialise(libraryVC)
            case let albumsVC as AlbumsVC:
                dependencyInjector.initialise(albumsVC)
            case let preferencesVC as PreferencesView:
                dependencyInjector.initialise(preferencesView: preferencesVC)
            default:
                assertionFailure()
            }
        }
    }
}
