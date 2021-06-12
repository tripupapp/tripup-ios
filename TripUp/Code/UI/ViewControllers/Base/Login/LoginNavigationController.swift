//
//  LoginNavigationController.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 08/09/2020.
//  Copyright © 2020 Vinoth Ramiah. All rights reserved.
//

import AVFoundation.AVPlayer
import Foundation
import UIKit

import AnimatedGradientView

class LoginNavigationController: UINavigationController, UIViewControllerAnimatedGradient {
    var animatedGradient: AnimatedGradientView?
    var animatedGradientEnterForegroundToken: NSObjectProtocol?
    var animatedGradientEnterBackgroundToken: NSObjectProtocol?

    private var audioPlayer: AVAudioPlayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        delegate = self

        setupAnimatedGradient()
        animatedGradient?.startAnimating()

        if let audioURL = Bundle.main.url(forResource: "intro-music", withExtension: "aac"), let audioPlayer = try? AVAudioPlayer(contentsOf: audioURL) {
            audioPlayer.prepareToPlay()
            audioPlayer.numberOfLoops = -1
            audioPlayer.play()
            audioPlayer.volume = 0.2    // volume is logarithmic - https://stackoverflow.com/a/30098872/2728986
            self.audioPlayer = audioPlayer
        }
    }

    deinit {
        removeAnimatedGradientObservers()
    }
}

extension LoginNavigationController: UINavigationControllerDelegate {
    func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {
        if let transparentVC = viewController as? UIViewControllerTransparent, transparentVC.transparent {
            if transparentVC.navigationBarHidden {
                if let currentVC = navigationController.topViewController as? UIViewControllerTransparent, currentVC.transparent {
                    navigationController.setNavigationBarHidden(true, animated: false)
                } else {
                    navigationController.setNavigationBarHidden(true, animated: animated)
                }
            } else {
                navigationController.setNavigationBarHidden(false, animated: animated)
                navigationController.navigationBar.setBackgroundImage(UIImage(), for: .default) // sets background to a blank/empty image
                navigationController.navigationBar.shadowImage = UIImage()                      // sets shadow (line below the bar) to a blank image
                navigationController.navigationBar.tintColor = .white
                navigationController.navigationBar.titleTextAttributes = [.foregroundColor: UIColor.white]
            }
        } else {
            navigationController.setNavigationBarHidden(false, animated: animated)
            // defaults, obtained from printing state before change
            navigationController.navigationBar.setBackgroundImage(nil, for: .default)
            navigationController.navigationBar.shadowImage = nil
            navigationController.navigationBar.tintColor = .systemBlue
            navigationController.navigationBar.titleTextAttributes = nil
        }
    }

    func navigationController(_ navigationController: UINavigationController, animationControllerFor operation: UINavigationController.Operation, from fromVC: UIViewController, to toVC: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        if let fromVC = fromVC as? UIViewControllerTransparent, fromVC.transparent, let toVC = toVC as? UIViewControllerTransparent, toVC.transparent {
            return TransparentViewControllerAnimator(operation: operation)
        } else {
            return nil
        }
    }
}

// source: https://stackoverflow.com/questions/18881427/ios-7-view-with-transparent-content-overlaps-previous-view#comment63197791_19512998
// reason: https://stackoverflow.com/a/21510602/2728986
private class TransparentViewControllerAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    let operation: UINavigationController.Operation

    init(operation: UINavigationController.Operation) {
        self.operation = operation
    }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        return 0.75
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        let container = transitionContext.containerView

        guard let fromVC = transitionContext.viewController(forKey: UITransitionContextViewControllerKey.from), let toVC = transitionContext.viewController(forKey: UITransitionContextViewControllerKey.to) else {
            return
        }

        let fromView = fromVC.view
        let toView = toVC.view

        let containerWidth = container.frame.width

        var toInitialFrame = container.frame
        var fromDestinationFrame = fromView?.frame

        if operation == .push {
            toInitialFrame.origin.x = containerWidth
            toView?.frame = toInitialFrame
            fromDestinationFrame?.origin.x = -containerWidth
        } else if operation == .pop {
            toInitialFrame.origin.x = -containerWidth
            toView?.frame = toInitialFrame
            fromDestinationFrame?.origin.x = containerWidth
        }

        toView?.isUserInteractionEnabled = false
        if let toView = toView, !container.subviews.contains(toView) {
            container.addSubview(toView)
        }

        UIView.animate(withDuration: transitionDuration(using: transitionContext), delay: 0.0, usingSpringWithDamping: 1000, initialSpringVelocity: 1, options: [], animations: {
            toView?.frame = container.frame
            fromView?.frame = fromDestinationFrame!
        }) { _ in
            toView?.frame = container.frame
            toView?.isUserInteractionEnabled = true
            fromView?.removeFromSuperview()
            transitionContext.completeTransition(true)
        }
    }
}
