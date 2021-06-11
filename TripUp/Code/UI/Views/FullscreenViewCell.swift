//
//  FullscreenViewCell.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 11/09/2019.
//  Copyright © 2019 Vinoth Ramiah. All rights reserved.
//

import Foundation
import UIKit

class FullscreenViewCell: UICollectionViewCell {
    static let reuseIdentifier = "AssetFullCell"

    @IBOutlet var imageView: UIImageView!
    @IBOutlet var avPlayerView: AVPlayerView!
    @IBOutlet var scrollView: UIScrollView!
    @IBOutlet var activityIndicator: UIActivityIndicatorView!
    @IBOutlet var originalMissingLabel: UILabel!

    var assetID: UUID!
    var zoomOccurred: Closure?
}

extension FullscreenViewCell: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        if imageView.image != nil {
            return imageView
        }
        if avPlayerView.player != nil {
            return avPlayerView
        }
        return nil
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        zoomOccurred?()
    }
}
