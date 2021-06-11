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
        guard asset.type == .video || asset.type == .audio else {
            DispatchQueue.main.async {
                callback(nil, nil)
            }
            return
        }
        if asset.imported {

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
                    requestOptions.deliveryMode = format == .fast ? .fastFormat : .highQualityFormat

                    self.iosImageManager.requestPlayerItem(forVideo: iosAsset, options: requestOptions) { (avPlayerItem, info) in
                        DispatchQueue.main.async {
                            callback(avPlayerItem, ResultInfo(final: true, uti: nil))
                        }
                    }
                }
            }
        }
    }
}
