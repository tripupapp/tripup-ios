//
//  AssetAVRequester.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 11/06/2021.
//  Copyright © 2021 Vinoth Ramiah. All rights reserved.
//

import Foundation
import class AVFoundation.AVPlayerItem

protocol AssetAVRequester {
    func requestAV(for asset: Asset, format: AssetManager.AVRequestFormat, callback: @escaping (_ avPlayerItem: AVPlayerItem?, _ info: AssetManager.ResultInfo?) -> Void)
}

extension AssetManager: AssetAVRequester {
    func requestAV(for asset: Asset, format: AVRequestFormat, callback: @escaping (AVPlayerItem?, ResultInfo?) -> Void) {
        let callbackOnMain = { (playerItem: AVPlayerItem?, resultInfo: ResultInfo?) -> Void in
            DispatchQueue.main.async {
                callback(playerItem, resultInfo)
            }
        }
        guard asset.type == .video else {
            log.warning("\(asset.uuid): incorrect asset type used - type: \(String(describing: asset.type))")
            assertionFailure()
            callbackOnMain(nil, nil)
            return
        }
        if asset.imported {
            switch format {
            case .best:
                loadAVPlayerItem(forAsset: asset, quality: .original, callback: callbackOnMain)
            case .fast:
                loadAVPlayerItem(forAsset: asset, quality: .low, callback: callbackOnMain)
            case .opportunistic:
                loadAVPlayerItem(forAsset: asset, quality: .low, finalCallback: false, callback: callbackOnMain)
                loadAVPlayerItem(forAsset: asset, quality: .original, finalCallback: true, callback: callbackOnMain)
            }
        } else {
            assetToPHAsset(asset) { [photoLibrary] (phAsset) in
                if let phAsset = phAsset {
                    photoLibrary.requestAVPlayerItem(forPHAsset: phAsset, format: format, callback: callbackOnMain)
                } else {
                    callbackOnMain(nil, nil)
                }
            }
        }
    }

    private func loadAVPlayerItem(forAsset asset: Asset, quality: Quality, finalCallback: Bool = true, callback: @escaping (AVPlayerItem?, ResultInfo?) -> Void) {
        load(asset: asset, atQuality: quality) { (url, uti) in
            if let url = url {
                let playerItem = AVPlayerItem(url: url)
                callback(playerItem, ResultInfo(final: finalCallback, uti: uti))
            } else {
                callback(nil, ResultInfo(final: finalCallback, uti: uti))
            }
        }
    }
}
