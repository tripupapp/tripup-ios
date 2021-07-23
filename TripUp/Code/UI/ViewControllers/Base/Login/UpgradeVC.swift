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
    @IBOutlet var initialViews: UIView!
    @IBOutlet var upgradingViews: [UIView]!
    @IBOutlet var imageView: UIImageView!
    @IBOutlet var progressView: UIProgressView!
    @IBOutlet var progressPercentage: UILabel!

    var upgradeOperation: UpgradeOperation?
    var transparent: Bool = true
    var navigationBarHidden: Bool = true

    private let operationQueue = OperationQueue()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        progressView.progress = 0
        progressPercentage.text = "0 %"
        if #available(iOS 13.0, *), let image = UIImage(systemName: "cpu") {
            imageView.image = image
        }
        upgradeOperation?.progressUpdateUI = { [weak self] (completed: Int, total: Int) in
            DispatchQueue.main.async {
                self?.progressView.isHidden = false
                self?.progressPercentage.isHidden = false
                if completed == total {
                    self?.progressView.setProgress(1.0, animated: true)
                    self?.progressPercentage.text = "100 %"
                } else {
                    let fraction = Float(completed) / Float(total)
                    self?.progressView.progress = fraction
                    self?.progressPercentage.text = "\(Int(fraction * 100)) %"
                }
            }
        }
    }

    @IBAction func beginUpgrade(_ sender: UIButton) {
        initialViews.isHidden = true
        upgradingViews.forEach{ $0.isHidden = false }
        operationQueue.addOperation(upgradeOperation!)
    }
}
