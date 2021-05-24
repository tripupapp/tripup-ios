//
//  UpgradeVC.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 25/11/2020.
//  Copyright © 2020 Vinoth Ramiah. All rights reserved.
//

import Foundation
import UIKit

class UpgradeVC: UIViewController, UIViewControllerTransparent {
    @IBOutlet var progressView: UIProgressView!

    weak var appDelegateExtension: AppDelegateExtension?
    var serverUpgrader: ServerUpgrader?
    var transparent: Bool = true
    var navigationBarHidden: Bool = true

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        progressView.progress = 0
        progressView.isHidden = true
        serverUpgrader?.progressUpdateUI = { [weak self] (completed: Int, total: Int) in
            DispatchQueue.main.async {
                self?.progressView.isHidden = false
                if completed == total {
                    self?.progressView.setProgress(1.0, animated: true)
                } else {
                    self?.progressView.progress = Float(completed) / Float(total)
                }
            }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard let appDelegateExtension = appDelegateExtension else {
            preconditionFailure()
        }
        let serverSchemaVersion = appDelegateExtension.serverSchemaVersion
        serverUpgrader?.upgrade(fromSchemaVersion: serverSchemaVersion, callback: { [weak self] (success) in
            guard let self = self else { return }
            if success {
                self.appDelegateExtension?.serverSchemaVersion = "1"
                self.appDelegateExtension?.presentNextRootViewController(after: self)
            } else {
                let alert = UIAlertController(title: "Upgrade failed", message: "There was an error upgrading your data. Please try again. If the problem persists, please contact us.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in
                    self.appDelegateExtension?.presentNextRootViewController(after: self, resetApp: true)
                }))
                self.present(alert, animated: true, completion: nil)
            }
        })
    }
}
