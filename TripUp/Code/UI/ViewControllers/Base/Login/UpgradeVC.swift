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

    var upgradeOperation: UpgradeOperation?
    var transparent: Bool = true
    var navigationBarHidden: Bool = true

    private let operationQueue = OperationQueue()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        progressView.progress = 0
        progressView.isHidden = true
        upgradeOperation?.progressUpdateUI = { [weak self] (completed: Int, total: Int) in
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
        operationQueue.addOperation(upgradeOperation!)
    }
}
