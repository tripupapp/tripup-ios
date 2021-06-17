//
//  AssetAVRequester.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 11/06/2021.
//  Copyright © 2021 Vinoth Ramiah. All rights reserved.
//

import Foundation
import AVFoundation.AVPlayer
import Photos.PHImageManager

protocol AssetAVRequester {
    func requestAV(for asset: Asset, format: AssetManager.AVRequestFormat, callback: @escaping (_ avPlayerItem: AVPlayerItem?, _ info: AssetManager.ResultInfo?) -> Void)
}

extension AssetManager: AssetAVRequester {
    func requestAV(for asset: Asset, format: AVRequestFormat, callback: @escaping (AVPlayerItem?, ResultInfo?) -> Void) {
        guard asset.type == .video else {
            log.warning("\(asset.uuid): incorrect asset type used - type: \(String(describing: asset.type))")
            assertionFailure()
            DispatchQueue.main.async {
                callback(nil, nil)
            }
            return
        }
        if asset.imported {
            switch format {
            case .best:
                loadAVPlayerItem(forAsset: asset, quality: .original, callbackOnMain: callback)
            case .fast:
                loadAVPlayerItem(forAsset: asset, quality: .low, callbackOnMain: callback)
            case .opportunistic:
                loadAVPlayerItem(forAsset: asset, quality: .low, finalCallback: false, callbackOnMain: callback)
                loadAVPlayerItem(forAsset: asset, quality: .original, finalCallback: true, callbackOnMain: callback)
            }
        } else {
            assetController.assetIDlocalIDMap { [weak self] (idMap) in
                guard let self = self, let localID = idMap[asset.uuid] else {
                    DispatchQueue.main.async {
                        callback(nil, nil)
                    }
                    return
                }
                self.photoLibrary.fetchAsset(withLocalIdentifier: localID) { [weak self] iosAsset in
                    precondition(Thread.isMainThread)
                    guard let self = self, let iosAsset = iosAsset else {
                        callback(nil, nil)
                        return
                    }

                    let requestOptions = PHVideoRequestOptions()
                    requestOptions.version = .current
                    requestOptions.isNetworkAccessAllowed = true
                    switch format {
                    case .best:
                        requestOptions.deliveryMode = .highQualityFormat
                    case .fast:
                        requestOptions.deliveryMode = .fastFormat
                    case .opportunistic:
                        requestOptions.deliveryMode = .automatic
                    }

                    self.iosImageManager.requestPlayerItem(forVideo: iosAsset, options: requestOptions) { (avPlayerItem, info) in
                        DispatchQueue.main.async {
                            callback(avPlayerItem, ResultInfo(final: true, uti: nil))
                        }
                    }
                }
            }
        }
    }

    private func loadAVPlayerItem(forAsset asset: Asset, quality: Quality, finalCallback: Bool = true, callbackOnMain callback: @escaping (AVPlayerItem?, ResultInfo?) -> Void) {
        load(asset: asset, atQuality: quality) { (url, uti) in
            if let url = url {
                let playerItem = AVPlayerItem(url: url)
                DispatchQueue.main.async {
                    callback(playerItem, ResultInfo(final: finalCallback, uti: uti))
                }
            } else {
                DispatchQueue.main.async {
                    callback(nil, ResultInfo(final: finalCallback, uti: uti))
                }
            }
        }
    }
}
