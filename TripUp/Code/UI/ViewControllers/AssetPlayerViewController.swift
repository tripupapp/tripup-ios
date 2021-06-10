//
//  AssetPlayerViewController.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 10/06/2021.
//  Copyright © 2021 Vinoth Ramiah. All rights reserved.
//

import Foundation
import AVKit.AVPlayerViewController
import UIKit.UIViewController

protocol AssetPlayerViewController: UIViewController {
    var mainContentView: UIView { get }
}

class PhotoPlayerViewController: UIViewController {
    @IBOutlet var imageView: UIImageView!
}

extension PhotoPlayerViewController: AssetPlayerViewController {
    var mainContentView: UIView {
        return imageView
    }
}

extension AVPlayerViewController: AssetPlayerViewController {
    var mainContentView: UIView {
        return view
    }
}
