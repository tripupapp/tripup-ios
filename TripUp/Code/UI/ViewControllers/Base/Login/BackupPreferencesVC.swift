//
//  BackupPreferencesVC.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 08/09/2020.
//  Copyright © 2020 Vinoth Ramiah. All rights reserved.
//

import Foundation
import UIKit

class BackupPreferencesVC: UIViewController, UIViewControllerTransparent {
    weak var appDelegateExtension: AppDelegateExtension?
    var transparent: Bool = true
    var navigationBarHidden: Bool = true

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        super.prepare(for: segue, sender: sender)
        if let cloudStorageVC = segue.destination as? CloudStorageVC {
            appDelegateExtension?.initialise(cloudStorageVC)
            cloudStorageVC.navigationBarHidden = false
            cloudStorageVC.isModal = false
            cloudStorageVC.endClosure = { [weak self, unowned cloudStorageVC] in
                self?.appDelegateExtension?.autoBackup = true
                self?.nextScreen(after: cloudStorageVC)
            }
        }
    }

    private func nextScreen(after viewController: UIViewController) {
        appDelegateExtension?.presentNextRootViewController(after: viewController)
    }

    @IBAction func doNotBackup(_ sender: UIButton) {
        appDelegateExtension?.autoBackup = false
        nextScreen(after: self)
    }
}
