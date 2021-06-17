//
//  AssetOperationDelegate.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 18/08/2020.
//  Copyright © 2020 Vinoth Ramiah. All rights reserved.
//

import Foundation
import Photos
import UIKit.UIImage

protocol AssetOperationDelegate: AnyObject {
    var keychainQueue: DispatchQueue { get }

    func newAssetKey() -> CryptoPrivateKey
    func key(for asset: AssetManager.MutableAsset) -> CryptoPrivateKey?

    func requestIOSAsset(withLocalID localID: String, callbackOn dispatchQueue: DispatchQueue, callback: @escaping (PHAsset?) -> Void)
    func requestImageDataFromIOS(with iosAsset: PHAsset) -> (Data?, String?)
    func exportVideoData(forIOSAsset iosAsset: PHAsset, toURL url: URL, callback: @escaping (Bool, AVFileType?) -> Void)
    func compressVideo(atURL url: URL, saveTo outputURL: URL, callback: @escaping (Bool) -> Void)
    func requestImageThumbnailFromIOS(localID: String, size: CGSize, scale: CGFloat, callback: @escaping (Data?) -> Void) -> Bool

    func unlinkedAsset(withMD5Hash md5: Data, callback: @escaping (Asset?) -> Void)
    func save(localIdentifier: String?, forAsset asset: Asset)
    
    func fileExists(at url: URL) -> Bool
    func write(_ data: Data, to url: URL) -> Bool
    func load(_ url: URL) -> Data?
    @discardableResult func delete(resourceAt url: URL) -> Bool

    func upload(fileAtURL localURL: URL, transferPriority: DataManager.Priority, callback: @escaping (URL?) -> Void)
    func downloadFile(at source: URL, to destination: URL, priority: DataManager.Priority, callback: @escaping ClosureBool)

    func createOnServer(assets: [AssetManager.MutableAsset], callback: @escaping (Result<[String: Int], Error>) -> Void)
    func writeOriginalToDB(assets: [AssetManager.MutableAsset], callback: @escaping ([String: Int]?) -> Void)
    func deleteFromDB(assets: [AssetManager.MutableAsset], callback: @escaping ClosureBool)
}

extension AssetManager: AssetOperationDelegate {
    // MARK: key functions
    func newAssetKey() -> CryptoPrivateKey  {
        assert(!Thread.isMainThread)
        assert(.notOn(assetManagerQueue))
        return keychainDelegate.newAssetKey()
    }

    func key(for asset: MutableAsset) -> CryptoPrivateKey? {
        assert(!Thread.isMainThread)
        assert(.notOn(assetManagerQueue))
        if let fingerprint = asset.fingerprint {
            return keychainDelegate.assetKey(forFingerprint: fingerprint)
        }
        return nil
    }

    // MARK: iOS data request functions
    func requestIOSAsset(withLocalID localID: String, callbackOn dispatchQueue: DispatchQueue, callback: @escaping (PHAsset?) -> Void) {
        photoLibrary.fetchAsset(withLocalIdentifier: localID, callbackOn: dispatchQueue) { asset in
            callback(asset)
        }
    }

    func requestImageDataFromIOS(with iosAsset: PHAsset) -> (Data?, String?) {
        assert(!Thread.isMainThread)
        assert(.notOn(assetManagerQueue))

        let requestOptions = PHImageRequestOptions()
        requestOptions.version = .current
        requestOptions.isNetworkAccessAllowed = true
        requestOptions.isSynchronous = true

        var imageData: Data?
        var imageUTI: String?
        iosImageManager.requestImageData(for: iosAsset, options: requestOptions) { (data: Data?, uti: String?, _: UIImage.Orientation, _: [AnyHashable : Any]?) in
            imageData = data
            imageUTI = uti
        }
        return (imageData, imageUTI)
    }

    func exportVideoData(forIOSAsset iosAsset: PHAsset, toURL url: URL, callback: @escaping (Bool, AVFileType?) -> Void) {
        let requestOptions = PHVideoRequestOptions()
        requestOptions.version = .current
        requestOptions.deliveryMode = .highQualityFormat
        requestOptions.isNetworkAccessAllowed = true

        iosImageManager.requestExportSession(forVideo: iosAsset, options: requestOptions, exportPreset: AVAssetExportPresetPassthrough) { [weak self] (exportSession, _) in
            guard let exportSession = exportSession else {
                callback(false, nil)
                return
            }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
            let uti: AVFileType = .mp4
            exportSession.outputURL = url
            exportSession.outputFileType = uti
            exportSession.exportAsynchronously(completionHandler: { [unowned exportSession] in
                if case .completed = exportSession.status {
                    callback(true, uti)
                } else {
                    self?.log.error("phassetid: \(iosAsset.localIdentifier) - error: \(String(describing: exportSession.error))")
                    callback(false, uti)
                }
            })
        }
    }

    func compressVideo(atURL url: URL, saveTo outputURL: URL, callback: @escaping (Bool) -> Void) {
        let asset = AVAsset(url: url)
        let preset = AVAssetExportPresetLowQuality
        let uti: AVFileType = .mp4
        AVAssetExportSession.determineCompatibility(ofExportPreset: preset, with: asset, outputFileType: uti) { isCompatible in
            guard isCompatible else {
                self.log.error("export session incompatible - sourceURL: \(String(describing: url)), preset: \(preset), uti: \(String(describing: uti))")
                callback(false)
                return
            }
            guard let exportSession = AVAssetExportSession(asset: asset, presetName: preset) else {
                callback(false)
                return
            }
            try? FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
            exportSession.outputURL = outputURL
            exportSession.outputFileType = uti
            exportSession.exportAsynchronously(completionHandler: { [unowned exportSession] in
                if case .completed = exportSession.status {
                    callback(true)
                } else {
                    self.log.error("sourceURL: \(String(describing: url)), destinationURL: \(String(describing: outputURL)) - error: \(String(describing: exportSession.error))")
                    callback(true)
                }
            })
        }
    }

    func requestImageThumbnailFromIOS(localID: String, size: CGSize, scale: CGFloat, callback: @escaping (Data?) -> Void) -> Bool {
        assert(!Thread.isMainThread)
        assert(.notOn(assetManagerQueue))
        guard let iosAsset = PHAsset.fetchAssets(withLocalIdentifiers: [localID], options: nil).firstObject else {
            log.error("PHAssetID: \(localID) is not available in Photo Library")
            callback(nil)
            return false
        }

        let requestOptions = PHImageRequestOptions()
        requestOptions.version = .current
        requestOptions.isNetworkAccessAllowed = true
        requestOptions.isSynchronous = true
        requestOptions.resizeMode = .fast
        requestOptions.deliveryMode = .highQualityFormat
        iosImageManager.requestImage(for: iosAsset, targetSize: CGSize(width: size.width * scale, height: size.height * scale), contentMode: .default, options: requestOptions) { (image, _) in
            callback(image?.jpegData(compressionQuality: 0.0))
        }
        return true
    }

    func unlinkedAsset(withMD5Hash md5: Data, callback: @escaping (Asset?) -> Void) {
        assetController.unlinkedAsset(withMD5Hash: md5, callback: callback)
    }

    func save(localIdentifier: String?, forAsset asset: Asset) {
        assetController.save(localIdentifier: localIdentifier, forAsset: asset)
    }

    // MARK: disk functions
    func fileExists(at url: URL) -> Bool {
        assert(!Thread.isMainThread)
        assert(.notOn(assetManagerQueue))
        let reachable = try? url.checkResourceIsReachable()
        return reachable ?? false
    }

    func write(_ data: Data, to url: URL) -> Bool {
        assert(!Thread.isMainThread)
        assert(.notOn(assetManagerQueue))
        do {
            try data.write(to: url, options: [.atomic])
        } catch CocoaError.fileNoSuchFile {
            log.verbose("create parent directory and try again")    // e.g. asset ownerid folder
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
                try data.write(to: url, options: [.atomic])
            } catch {
                log.error("error writing data to disk – destination: \(url.absoluteString), error: \(String(describing: error))")
                return false
            }
        } catch {
            log.error("error writing data to disk – destination: \(url.absoluteString), error: \(String(describing: error))")
            return false
        }
        return true
    }

    func load(_ url: URL) -> Data? {
        assert(!Thread.isMainThread)
        assert(.notOn(assetManagerQueue))
        var data: Data?
        do {
            data = try Data(contentsOf: url)
        } catch {
            log.verbose("error reading from disk – source: \(String(describing: url)), error: \(String(describing: error))")
        }
        return data
    }

     @discardableResult func delete(resourceAt url: URL) -> Bool {
        assert(!Thread.isMainThread)
        assert(.notOn(assetManagerQueue))
        do {
            try FileManager.default.removeItem(at: url)
        } catch CocoaError.fileNoSuchFile {
        } catch {
            log.error("error deleting file: \(url.absoluteString), error: \(String(describing: error))")
            return false
        }
        return true
    }

    // MARK: cloud functions
    func upload(fileAtURL localURL: URL, transferPriority: DataManager.Priority, callback: @escaping (URL?) -> Void) {
        dataService.uploadFile(at: localURL) { url in
            callback(url)
        }
    }

    func downloadFile(at source: URL, to destination: URL, priority: DataManager.Priority, callback: @escaping ClosureBool) {
        dataService.downloadFile(at: source, to: destination) { success in
            callback(success)
        }
    }

    // MARK: server functions
    func createOnServer(assets: [MutableAsset], callback: @escaping (Result<[String: Int], Error>) -> Void) {
        keychainQueue.async { [weak self] in
            guard let self = self else {
                return
            }
            let userKey = self.keychainDelegate.primaryUserKey
            let assetKeys = assets.compactMap{ self.key(for: $0) }
            DispatchQueue.global().async {
                guard assetKeys.count == assets.count else {
                    self.log.debug("asset keys count mismatch")
                    callback(.failure("asset keys count mismatch"))
                    assertionFailure()
                    return
                }
                var jsonArray = [[String: Any]]()
                for (index, asset) in assets.enumerated() {
                    var json: [String: Any] = [
                        "assetID": asset.uuid.string,
                        "type": asset.type.rawValue,
                        "remotePath": asset.physicalAssets.low.remotePath!.absoluteString,
                        "pixelWidth": Int(asset.pixelSize.width),
                        "pixelHeight": Int(asset.pixelSize.height),
                    ]
                    if let originalUTI = asset.originalUTI?.rawValue {
                        json["originalUTI"] = originalUTI
                    }
                    if let remotePathOrig = asset.physicalAssets.original.remotePath?.absoluteString {
                        json["remotePathOrig"] = remotePathOrig
                    }

                    let assetKey = assetKeys[index]
                    autoreleasepool {
                        json["md5"] = assetKey.encrypt(asset.md5!.base64EncodedString(), signed: assetKey)
                        json["key"] = userKey.encrypt(assetKey.private, signed: userKey)
                        if let createDate = asset.creationDate {
                            json["createDate"] = assetKey.encrypt(createDate.iso8601, signed: assetKey)
                        }
                        if let locationString = asset.location?.serializedString {
                            json["location"] = assetKey.encrypt(locationString, signed: assetKey)
                        }
                        if let durationString = asset.duration?.description {
                            json["duration"] = assetKey.encrypt(durationString, signed: assetKey)
                        }
                    }
                    jsonArray.append(json)
                }
                self.webAPI.create(assets: jsonArray, callbackOn: .global()) { result in
                    callback(result)
                }
            }
        }
    }

    func writeOriginalToDB(assets: [MutableAsset], callback: @escaping ([String: Int]?) -> Void) {
        let assetsOriginalPaths = assets.reduce(into: [String: String]()) {
            $0[$1.uuid.string] = $1.physicalAssets.original.remotePath!.absoluteString
        }
        webAPI.update(assetsOriginalRemotePaths: assetsOriginalPaths, callbackOn: .global()) { (success, cloudFilesizes) in
            if success, let cloudFilesizes = cloudFilesizes {
                callback(cloudFilesizes)
            } else {
                callback(nil)
            }
        }
    }

    func deleteFromDB(assets: [MutableAsset], callback: @escaping ClosureBool) {
        webAPI.delete(assetIDs: assets.map{ $0.uuid.string }, callbackOn: assetManagerQueue) { success in
            callback(success)
        }
    }
}
