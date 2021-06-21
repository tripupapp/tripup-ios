//
//  AssetDataRequester.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 18/08/2020.
//  Copyright © 2020 Vinoth Ramiah. All rights reserved.
//

import Foundation
import Photos.PHAsset
import struct AVFoundation.AVFileType

protocol AssetDataRequester: AssetImageRequester, AssetAVRequester {
    func requestOriginalFile(forAsset asset: Asset, callback: @escaping (URL?) -> Void)
}

extension AssetManager: AssetDataRequester {
    func requestOriginalFile(forAsset asset: Asset, callback: @escaping (URL?) -> Void) {
        let callbackOnMain = { (url: URL?) -> Void in
            DispatchQueue.main.async {
                callback(url)
            }
        }
        if asset.imported {
            load(asset: asset, atQuality: .original) { (url, _) in
                callbackOnMain(url)
            }
        } else {
            switch asset.type {
            case .photo:    // using URLs for photo sharing as UIImage/Data cause memory exhaustion when sharing 30+ photos
                assetToPHAsset(asset) { [photoLibrary] (phAsset) in
                    guard let phAsset = phAsset,
                          let phAssetResource = photoLibrary.resource(forPHAsset: phAsset, type: .photo),
                          let url = FileManager.default.createUniqueTempFile(filename: asset.uuid.string, fileExtension: AVFileType(phAssetResource.uniformTypeIdentifier).fileExtension ?? "") else {
                        callbackOnMain(nil)
                        return
                    }
                    photoLibrary.write(resource: phAssetResource, toURL: url) { (success) in
                        if success {
                            callbackOnMain(url)
                        } else {
                            callbackOnMain(nil)
                        }
                    }
                }

            case .video:
                assetToPHAsset(asset) { [photoLibrary] (phAsset) in
                    guard let phAsset = phAsset else {
                        callbackOnMain(nil)
                        return
                    }
                    photoLibrary.transcodeVideoToMP4(forPHAsset: phAsset) { (output) in
                        callbackOnMain(output?.0)
                    }
                }

            case .audio, .unknown:
                fatalError()
            }
        }
    }

    func assetToPHAsset(_ asset: Asset, callback: @escaping (PHAsset?) -> Void) {
        assetController.localIdentifier(forAsset: asset) { [weak self] (id) in
            guard let id = id else {
                self?.log.error("assetid: \(asset.uuid.string) - localIdentifier missing")
                callback(nil)
                return
            }
            self?.photoLibrary.fetchAsset(withLocalIdentifier: id, callbackOn: .global()) { (phAsset) in
                if let phAsset = phAsset {
                    callback(phAsset)
                } else {
                    self?.log.error("assetid: \(asset.uuid.string) - phAsset missing")
                    callback(nil)
                }
            }
        }
    }
}
