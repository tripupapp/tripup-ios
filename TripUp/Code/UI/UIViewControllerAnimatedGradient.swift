//
//  UIViewControllerAnimatedGradient.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 28/03/2021.
//  Copyright © 2021 Vinoth Ramiah. All rights reserved.
//

import Foundation
import UIKit

import AnimatedGradientView

protocol UIViewControllerAnimatedGradient: UIViewController {
    var animatedGradient: AnimatedGradientView? { get set }
    var animatedGradientEnterForegroundToken: NSObjectProtocol? { get set }
    var animatedGradientEnterBackgroundToken: NSObjectProtocol? { get set }
}

extension UIViewControllerAnimatedGradient {
    func setupAnimatedGradient() {
        animatedGradient = AnimatedGradientView(frame: view.bounds)
        animatedGradient?.autoAnimate = true
        animatedGradient?.type = .axial
        animatedGradient?.animationValues = [                                // Gradient values from https://uigradients.com/
            (colors: ["#FDC830", "#F37335"], .up, .axial),                  // citrus peel
            (colors: ["#8A2387", "#E94057", "#F27121"], .right, .axial),    // wiretap
            (colors: ["#1a2a6c", "#fdbb2d"], .downRight, .axial),           // king yana (minus red middle component)
            (colors: ["#1a2a6c", "#b21f1f", "#fdbb2d"], .down, .axial),     // king yana
            (colors: ["#A83279", "#D38312"], .downLeft, .axial),            // crazy orange 1 (flipped)
            (colors: ["#23074d", "#cc5333"], .left, .axial),                // taran tado
            (colors: ["#ee0979", "#ff6a00"], .upLeft, .axial)]              // ibiza sunset
        view.addSubview(animatedGradient!)
        view.sendSubviewToBack(animatedGradient!)

        animatedGradientEnterForegroundToken = NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main, using: { [weak self] (notification) in
            self?.animatedGradient?.startAnimating()
        })
        animatedGradientEnterBackgroundToken = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main, using: { [weak self] (notification) in
            self?.animatedGradient?.stopAnimating()
        })
    }

    func removeAnimatedGradientObservers() {
        if let token = animatedGradientEnterForegroundToken {
            NotificationCenter.default.removeObserver(token)
        }
        if let token = animatedGradientEnterBackgroundToken {
            NotificationCenter.default.removeObserver(token)
        }
    }
}
