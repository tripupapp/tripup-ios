//
//  PhotoViewCell.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 10/09/2019.
//  Copyright © 2019 Vinoth Ramiah. All rights reserved.
//

import Foundation
import UIKit

import TripUpViews

class PhotoViewCell: UICollectionViewCell {
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

    static let reuseIdentifier = "AssetCell"

    @IBOutlet var imageView: UIImageView!
    @IBOutlet var activityIndicator: UIActivityIndicatorView!
    @IBOutlet var shareIcon: UIImageView!
    @IBOutlet var checkmarkIcon: UIImageView!
    @IBOutlet var gradientView: UIGradientView!
    @IBOutlet var assetContents: UIView!
    @IBOutlet var shareActionIcon: UIImageView!
    @IBOutlet var unshareActionIcon: UIImageView!
    @IBOutlet var shareActionIconSmallConstraint: NSLayoutConstraint!
    @IBOutlet var shareActionIconLargeConstraint: NSLayoutConstraint!
    @IBOutlet var unshareActionIconSmallConstraint: NSLayoutConstraint!
    @IBOutlet var unshareActionIconLargeConstraint: NSLayoutConstraint!
    @IBOutlet var actionIconContents: UIView!

    var assetID: UUID!
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
    var allIconsHidden: Bool {
        return shareIcon.isHidden
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        /*
         tintColorDidChange fixes tintColor not being set from storyboard when cell is first created (seems fine once a cell is reused though)
         https://stackoverflow.com/questions/41121425/uiimageview-doesnt-always-tint-template-image - apple radar: http://www.openradar.me/radar?id=5005434293321728
         https://stackoverflow.com/questions/52992077/uiimageview-tint-color-weirdness - apple radar: http://openradar.appspot.com/23759908
         not sure which one is the issue
         - This issue did not appear in XCode 9, iOS 11 SDK, iPhone X running iOS 11.4.1
         - Only presented itself once upgraded to XCode 10, still on iOS 11 SDK, iPhone X running iOS 11.4.1
         - Fixed in Xcode 11.3.1: fixed for iOS 13.3 iPhone X simulator, still broken for iOS 12.4 iPhone 5S simulator
        */
        if #available(iOS 13.0, *) {} else {
            shareIcon.tintColorDidChange()
        }
    }

    func showActionIcon(share: Bool) {
        shareActionIcon.isHidden = !share
        unshareActionIcon.isHidden = share
        actionIconContents.backgroundColor = share ? UIColor.init(red: 35/255, green: 187/255, blue: 42/255, alpha: 1) : UIColor.init(red: 241/255, green: 183/255, blue: 9/255, alpha: 1)
    }
}
