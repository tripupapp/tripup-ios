//
//  AVPlayerView.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 11/06/2021.
//  Copyright © 2021 Vinoth Ramiah. All rights reserved.
//

import Foundation
import AVFoundation
import UIKit.UIView

class AVPlayerView: UIView {
    // Override the property to make AVPlayerLayer the view's backing layer.
    override static var layerClass: AnyClass {
        AVPlayerLayer.self
    }

    // The associated player object.
    var player: AVPlayer? {
        get {
            playerLayer.player
        }
        set {
            playerLayer.player = newValue
        }
    }

    func fill() {
        playerLayer.videoGravity = .resizeAspectFill
    }

    private var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }
}
