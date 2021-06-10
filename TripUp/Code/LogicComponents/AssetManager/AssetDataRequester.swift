//
//  DataRequester.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 18/08/2020.
//  Copyright © 2020 Vinoth Ramiah. All rights reserved.
//

import Foundation
import Photos
import UIKit.UIImage

protocol AssetDataRequester {
    func requestImage(for asset: Asset, format: AssetManager.RequestFormat, callback: @escaping (_ image: UIImage?, _ info: AssetManager.ResultInfo?) -> Void)
    func requestImageData(for asset: Asset, format: AssetManager.RequestFormat, callback: @escaping (_ imageData: Data?, _ info: AssetManager.ResultInfo?) -> Void)
}

extension AssetManager: AssetDataRequester {
    func requestImage(for asset: Asset, format: RequestFormat, callback: @escaping (_ image: UIImage?, _ info: ResultInfo?) -> Void) {
        precondition(Thread.isMainThread)
        guard asset.type != .unknown else {
            fatalError()
        }
        guard asset.type != .audio else {
            fatalError()
        }
        if asset.imported {
            requestImageData(for: asset, format: format) { (data, info) in
                precondition(Thread.isMainThread)
                if let data = data {
                    DispatchQueue.global().async {
                        let image = UIImage(data: data)
                        DispatchQueue.main.async {
                            callback(image, info)
                        }
                    }
                } else {
                    callback(nil, info)
                }
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
                    let requestOptions = PHImageRequestOptions()
                    requestOptions.isSynchronous = false
                    requestOptions.version = .current
                    requestOptions.resizeMode = .fast
                    requestOptions.isNetworkAccessAllowed = true

                    var requestSize: CGSize!
                    switch format {
                    case .best:
                        requestOptions.deliveryMode = .highQualityFormat
                        requestSize = PHImageManagerMaximumSize
                    case .highQuality(let size, let scale), .lowQuality(let size, let scale):
                        requestOptions.deliveryMode = .opportunistic
                        requestSize = CGSize(width: size.width * scale, height: size.height * scale)
                    case .fast:
                        requestOptions.deliveryMode = .fastFormat
                        requestSize = PHImageManagerMaximumSize
                    }

                    self.iosImageManager.requestImage(for: iosAsset, targetSize: requestSize, contentMode: .default, options: requestOptions) { (image, info) in
                        precondition(Thread.isMainThread)
                        switch format {
                        case .best:
                            callback(image, ResultInfo(final: true, uti: nil))
                        case .highQuality(_, _), .lowQuality(_, _):
                            let degradedValue = info?[PHImageResultIsDegradedKey] as? NSNumber
                            let degraded = degradedValue?.boolValue ?? false
                            callback(image, ResultInfo(final: !degraded, uti: nil))
                        case .fast:
                            callback(image, ResultInfo(final: true, uti: nil))
                        }
                    }
                }
            }
        }
    }

    func loadDataOpportunistically(for asset: Asset, atQuality quality: Quality, size targetSize: CGSize, scale: CGFloat, callback: @escaping (_ imageData: Data?, _ info: ResultInfo?) -> Void) {
        precondition(Thread.isMainThread)
        var higherQualityLoaded = false
        loadData(for: asset, atQuality: quality) { (data, uti) in
            precondition(Thread.isMainThread)
            guard let data = data else { callback(nil, ResultInfo(final: true, uti: uti)); return }
            DispatchQueue.global(qos: .utility).async {
                let resizedData = data.downsample(to: targetSize, scale: scale, compress: false)
                DispatchQueue.main.async {
                    higherQualityLoaded = true
                    callback(resizedData, ResultInfo(final: true, uti: uti))
                }
            }
        }
        loadData(for: asset, atQuality: .low) { (data, uti) in
            precondition(Thread.isMainThread)
            guard !higherQualityLoaded else { return }
            callback(data, ResultInfo(final: false, uti: uti))
        }
    }

    func requestImageData(for asset: Asset, format: RequestFormat, callback: @escaping (_ imageData: Data?, _ info: ResultInfo?) -> Void) {
        if asset.imported {
            switch format {
            case .best:
                loadData(for: asset, atQuality: .original) { (data, uti) in
                    precondition(Thread.isMainThread)
                    callback(data, ResultInfo(final: true, uti: uti))
                }
            case .highQuality(let size, let scale):
                loadDataOpportunistically(for: asset, atQuality: .original, size: size, scale: scale, callback: callback)
            case .lowQuality(let size, let scale):
                loadDataOpportunistically(for: asset, atQuality: .low, size: size, scale: scale, callback: callback)
            case .fast:
                loadData(for: asset, atQuality: .low) { (data, uti) in
                    precondition(Thread.isMainThread)
                    callback(data, ResultInfo(final: true, uti: uti))
                }
            }
        } else {
            guard asset.type == .photo else {
                assertionFailure()
                DispatchQueue.main.async {
                    callback(nil, nil)
                }
                return
            }
            assetController.assetIDlocalIDMap { [weak self] (idMap) in
                guard let self = self, let localID = idMap[asset.uuid] else {
                    DispatchQueue.main.async {
                        callback(nil, nil)
                    }
                    return
                }
                self.photoLibrary.fetchAsset(withLocalIdentifier: localID) { [weak self] iosAsset in
                    guard let self = self, let iosAsset = iosAsset else {
                        DispatchQueue.main.async {
                            callback(nil, nil)
                        }
                        return
                    }
                    let requestOptions = PHImageRequestOptions()
                    requestOptions.isSynchronous = false
                    requestOptions.version = .current
                    requestOptions.isNetworkAccessAllowed = true

                    self.iosImageManager.requestImageData(for: iosAsset, options: requestOptions) { (data: Data?, uti: String?, _: UIImage.Orientation, _: [AnyHashable : Any]?) in
                        precondition(Thread.isMainThread)
                        switch format {
                        case .best, .fast:
                            callback(data, ResultInfo(final: true, uti: AVFileType(uti)))
                        case .highQuality(let size, let scale):
                            DispatchQueue.global(qos: .utility).async {
                                let resizedData = data?.downsample(to: size, scale: scale, compress: false)
                                DispatchQueue.main.async {
                                    callback(resizedData, ResultInfo(final: true, uti: AVFileType(uti)))
                                }
                            }
                        case .lowQuality(let size, let scale):
                            DispatchQueue.global(qos: .utility).async {
                                let resizedData = data?.downsample(to: size, scale: scale, compress: true)
                                DispatchQueue.main.async {
                                    callback(resizedData, ResultInfo(final: true, uti: AVFileType(uti)))
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
