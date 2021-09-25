//
//  AlbumCollectionViewCell.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 10/09/2019.
//  Copyright © 2019 Vinoth Ramiah. All rights reserved.
//

import Foundation
import UIKit

import TripUpViews

class AlbumCollectionViewCell: UICollectionViewCell, CollectionViewCell {
    struct ConstraintPair {
        let small: NSLayoutConstraint
        let large: NSLayoutConstraint

        var isZoomed: Bool {
            get {
                return large.priority == UILayoutPriority.defaultHigh
            }
            nonmutating set {
                if newValue {
                    small.priority = UILayoutPriority.defaultLow
                    large.priority = UILayoutPriority.defaultHigh
                } else {
                    large.priority = UILayoutPriority.defaultLow
                    small.priority = UILayoutPriority.defaultHigh
                }
            }
        }
    }

    static let reuseIdentifier = "AlbumCollectionViewCell"

    @IBOutlet var imageView: UIImageView!
    @IBOutlet var activityIndicator: UIActivityIndicatorView!
    @IBOutlet var topGradient: UIGradientView!
    @IBOutlet var bottomGradient: UIGradientView!
    @IBOutlet var checkmarkView: UIImageView!
    @IBOutlet var durationLabel: UILabel!

    @IBOutlet var shareIcon: UIImageView!
    @IBOutlet var assetContents: UIView!
    @IBOutlet var shareActionIcon: UIImageView!
    @IBOutlet var unshareActionIcon: UIImageView!
    @IBOutlet var shareActionIconSmallConstraint: NSLayoutConstraint!
    @IBOutlet var shareActionIconLargeConstraint: NSLayoutConstraint!
    @IBOutlet var unshareActionIconSmallConstraint: NSLayoutConstraint!
    @IBOutlet var unshareActionIconLargeConstraint: NSLayoutConstraint!
    @IBOutlet var actionIconContents: UIView!

    lazy var shareActionIconConstraint: ConstraintPair = {
        return ConstraintPair(
            small: shareActionIconSmallConstraint,
            large: shareActionIconLargeConstraint
        )
    }()
    lazy var unshareActionIconConstraint: ConstraintPair = {
        return ConstraintPair(
            small: unshareActionIconSmallConstraint,
            large: unshareActionIconLargeConstraint
        )
    }()
    var bottomIconsHidden: Bool {
        return shareIcon.isHidden
    }

    var assetID: UUID!

    func showActionIcon(share: Bool) {
        shareActionIcon.isHidden = !share
        unshareActionIcon.isHidden = share
        actionIconContents.backgroundColor = share ? UIColor.init(red: 35/255, green: 187/255, blue: 42/255, alpha: 1) : UIColor.init(red: 241/255, green: 183/255, blue: 9/255, alpha: 1)
    }
}
