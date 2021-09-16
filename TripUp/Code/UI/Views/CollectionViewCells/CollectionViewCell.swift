//
//  CollectionViewCell.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 16/09/2021.
//  Copyright © 2021 Vinoth Ramiah. All rights reserved.
//

import Foundation
import UIKit

import TripUpViews

protocol CollectionViewCell: UICollectionViewCell {
    static var reuseIdentifier: String { get }

    var imageView: UIImageView! { get set }
    var activityIndicator: UIActivityIndicatorView! { get set }
    var topGradient: UIGradientView! { get set }
    var bottomGradient: UIGradientView! { get set }
    var checkmarkView: UIImageView! { get set }
    var durationLabel: UILabel! { get set }

    var assetID: UUID! { get set }
    var topIconsHidden: Bool { get }
    var bottomIconsHidden: Bool { get }

    func select()
    func deselect()
}

extension CollectionViewCell {
    var topIconsHidden: Bool {
        return durationLabel.text?.isEmpty ?? true
    }

    func select() {
        checkmarkView.isHidden = false
        imageView.alpha = 0.75
    }

    func deselect() {
        checkmarkView.isHidden = true
        imageView.alpha = 1.0
    }
}
