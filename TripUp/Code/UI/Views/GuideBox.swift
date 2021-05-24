//
//  GuideBox.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 04/06/2020.
//  Copyright © 2020 Vinoth Ramiah. All rights reserved.
//

import Foundation
import UIKit

class GuideBox: UIViewController {
    @IBOutlet var innerView: UIView!

    var dismissCallback: Closure?

    override func viewDidLoad() {
        super.viewDidLoad()
        innerView.layer.cornerRadius = 15
        innerView.layer.shadowRadius = 5
        innerView.layer.shadowOffset = .zero
        innerView.layer.shadowOpacity = 1
        innerView.layer.shadowColor = UIColor.lightGray.cgColor
    }

    @IBAction func dismiss() {
        UIView.animate(withDuration: 0.3, animations: {
            self.view.alpha = 0
        }) { _ in
            self.willMove(toParent: nil)
            self.removeFromPhotoView()
            self.dismissCallback?()
        }
    }

    func removeFromPhotoView() {
        view.removeFromSuperview()
        removeFromParent()
    }
}
