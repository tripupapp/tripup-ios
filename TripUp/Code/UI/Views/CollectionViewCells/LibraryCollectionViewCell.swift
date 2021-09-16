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
            importedIcon.tintColorDidChange()
            importingIcon.tintColorDidChange()
        }
    }
}
