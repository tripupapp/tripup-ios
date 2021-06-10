//
//  FullscreenViewCell.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 11/09/2019.
//  Copyright © 2019 Vinoth Ramiah. All rights reserved.
//

import Foundation
import UIKit
import AVKit.AVPlayerViewController

class FullscreenViewCell: UICollectionViewCell {
    static let reuseIdentifier = "AssetFullCell"

    @IBOutlet var scrollView: UIScrollView!
    @IBOutlet var activityIndicator: UIActivityIndicatorView!
    @IBOutlet var originalMissingLabel: UILabel!

    var assetID: UUID!
    var playerViewController: AssetPlayerViewController?
    var playerViewControllerConstraints: [NSLayoutConstraint]?
    var zoomOccurred: Closure?
}

extension FullscreenViewCell {
    func requestPhotoPlayer(assignParentViewController parentViewController: UIViewController) -> PhotoPlayerViewController {
        return requestPlayer(withIdentifier: "photo", assignParentViewController: parentViewController)
    }

    func requestAVPlayer(assignParentViewController parentViewController: UIViewController) -> AVPlayerViewController {
        return requestPlayer(withIdentifier: "audiovideo", assignParentViewController: parentViewController)
    }

    private func requestPlayer<T>(withIdentifier identifier: String, assignParentViewController parentViewController: UIViewController) -> T where T: AssetPlayerViewController {
        if let playerViewController = playerViewController {
            if let playerViewController = playerViewController as? T {
                return playerViewController
            }
            playerViewController.willMove(toParent: nil)
            NSLayoutConstraint.deactivate(playerViewControllerConstraints!)
            playerViewController.view.removeFromSuperview()
            playerViewController.removeFromParent()
        }
        let playerViewController = UIStoryboard(name: "AssetPlayers", bundle: .main).instantiateViewController(withIdentifier: identifier) as! T
        parentViewController.addChild(playerViewController)
        scrollView.addSubview(playerViewController.view)

        let constraints = [
            scrollView.leadingAnchor.constraint(equalTo: playerViewController.view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: playerViewController.view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: playerViewController.view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: playerViewController.view.bottomAnchor),
            scrollView.centerXAnchor.constraint(equalTo: playerViewController.view.centerXAnchor),
            scrollView.centerYAnchor.constraint(equalTo: playerViewController.view.centerYAnchor)
        ]
        NSLayoutConstraint.activate(constraints)
        playerViewController.didMove(toParent: parentViewController)

        self.playerViewController = playerViewController
        playerViewControllerConstraints = constraints
        return playerViewController
    }
}

extension FullscreenViewCell: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return playerViewController?.view
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        zoomOccurred?()
    }
}
