//
//  AssetDataRequester.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 18/08/2020.
//  Copyright © 2020 Vinoth Ramiah. All rights reserved.
//

import Foundation
import AVFoundation
import Photos.PHAsset

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
                assetToPHAsset(asset) { [weak self] (phAsset) in
                    guard let self = self else {
                        return
                    }
                    guard let phAsset = phAsset else {
                        callbackOnMain(nil)
                        return
                    }
                    let (data, uti) = self.requestImageDataFromIOS(with: phAsset)
                    guard let imageData = data else {
                        self.log.error("assetid: \(asset.uuid.string) - image data missing")
                        callbackOnMain(nil)
                        return
                    }
                    // url last component used as filename of shared file
                    let tempURL = self.generateUniqueTempFile(filename: asset.uuid.string, fileExtension: AVFileType(uti)?.fileExtension ?? "")
                    if self.write(imageData, to: tempURL) {
                        callbackOnMain(tempURL)
                    } else {
                        callbackOnMain(nil)
                    }
                }

            case .video:
                assetToPHAsset(asset) { [weak self] (phAsset) in
                    guard let self = self else {
                        return
                    }
                    guard let phAsset = phAsset else {
                        callbackOnMain(nil)
                        return
                    }
                    // url last component used as filename of shared file
                    let tempURL = self.generateUniqueTempFile(filename: asset.uuid.string, fileExtension: "mp4")
                    self.exportVideoData(forIOSAsset: phAsset, toURL: tempURL) { (success, _) in
                        callbackOnMain(success ? tempURL : nil)
                    }
                }

            case .audio, .unknown:
                assertionFailure()
            }
        }
    }

    private func assetToPHAsset(_ asset: Asset, callback: @escaping (PHAsset?) -> Void) {
        assetController.localIdentifier(forAsset: asset) { [weak self] (id) in
            guard let id = id else {
                self?.log.error("assetid: \(asset.uuid.string) - localIdentifier missing")
                callback(nil)
                return
            }
            self?.requestIOSAsset(withLocalID: id, callbackOn: .global()) { (phAsset) in
                if let phAsset = phAsset {
                    callback(phAsset)
                } else {
                    self?.log.error("assetid: \(asset.uuid.string) - phAsset missing")
                    callback(nil)
                }
            }
        }
    }

    private func generateUniqueTempFile(filename: String, fileExtension: String) -> URL {
        let tempDir = Globals.Directories.tmp.appendingPathComponent("\(ProcessInfo().globallyUniqueString)", isDirectory: true)
        return tempDir.appendingPathComponent(filename, isDirectory: false).appendingPathExtension(fileExtension)
    }
}
