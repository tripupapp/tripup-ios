//
//  LibraryCollectionViewCell.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 16/09/2021.
//  Copyright © 2021 Vinoth Ramiah. All rights reserved.
//

import Foundation
import UIKit

import TripUpViews

class LibraryCollectionViewCell: UICollectionViewCell, CollectionViewCell  {
    static let reuseIdentifier = "LibraryCollectionViewCell"

    @IBOutlet var imageView: UIImageView!
    @IBOutlet var activityIndicator: UIActivityIndicatorView!
    @IBOutlet var topGradient: UIGradientView!
    @IBOutlet var bottomGradient: UIGradientView!
    @IBOutlet var checkmarkView: UIImageView!
    @IBOutlet var durationLabel: UILabel!

    @IBOutlet var lockView: UIView!
    @IBOutlet var lockIcon: UIImageView!
    // use 2 separate icons for this, because we use System Symbols in iOS 13+, which don't behave well when switching image with different aspect ratio
    @IBOutlet var importedIcon: UIImageView!
    @IBOutlet var importingIcon: UIImageView!

    var bottomIconsHidden: Bool {
        return importedIcon.isHidden && importingIcon.isHidden
    }

    var assetID: UUID!
}
