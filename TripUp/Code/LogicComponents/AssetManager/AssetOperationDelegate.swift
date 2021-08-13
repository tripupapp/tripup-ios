//
//  AssetOperationDelegate.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 18/08/2020.
//  Copyright © 2020 Vinoth Ramiah. All rights reserved.
//

import Foundation
import AVFoundation
import CommonCrypto
import MobileCoreServices.UTCoreTypes

protocol AssetOperationDelegate: AnyObject {
    var keychainQueue: DispatchQueue { get }
    var photoLibrary: PhotoLibrary { get }

    func newAssetKey() -> CryptoPrivateKey
    func key(for asset: AssetManager.MutableAsset) -> CryptoPrivateKey?

    func unlinkedAsset(withMD5Hash md5: Data, callback: @escaping (Asset?) -> Void)
    func `switch`(localIdentifier: String, fromAssetID oldAssetID: UUID, toAssetID newAssetID: UUID)
    
    func fileExists(at url: URL) -> Bool
    func write(_ data: Data, to url: URL) -> Bool
    func load(_ url: URL) -> Data?
    @discardableResult func delete(resourceAt url: URL) -> Bool
    func md5(ofFileAtURL url: URL) -> Data?
    func downsample(imageAt imageSourceURL: URL, originalSize size: CGSize, toScale scale: CGFloat, compress: Bool, destination imageDestinationURL: URL) -> Bool
    func compressVideo(atURL url: URL, callback: @escaping (URL?) -> Void)

    func upload(fileAtURL localURL: URL, transferPriority: DataManager.Priority, callback: @escaping (URL?) -> Void)
    func downloadFile(at source: URL, to destination: URL, priority: DataManager.Priority, callback: @escaping ClosureBool)

    func createOnServer(assets: [AssetManager.MutableAsset], callback: @escaping (Result<[String: Int], Error>) -> Void)
    func writeOriginalToDB(assets: [AssetManager.MutableAsset], callback: @escaping ([String: Int]?) -> Void)
    func deleteFromDB(assets: [AssetManager.MutableAsset], callback: @escaping ClosureBool)
}

class AssetOperationDelegateObject: AssetOperationDelegate {
    weak var keychainDelegate: KeychainDelegate?

    let keychainQueue: DispatchQueue
    let photoLibrary: PhotoLibrary

    private let log = Logger.self
    private let dataService: DataService
    private let webAPI: API
    private let assetController: AssetController

    init(assetController: AssetController, dataService: DataService, webAPI: API, photoLibrary: PhotoLibrary, keychainQueue: DispatchQueue) {
        self.dataService = dataService
        self.webAPI = webAPI
        self.assetController = assetController
        self.keychainQueue = keychainQueue
        self.photoLibrary = photoLibrary
    }

    // MARK: key functions
    func newAssetKey() -> CryptoPrivateKey  {
        assert(!Thread.isMainThread)
        return keychainDelegate!.newAssetKey()
    }

    func key(for asset: AssetManager.MutableAsset) -> CryptoPrivateKey? {
        assert(!Thread.isMainThread)
        if let fingerprint = asset.fingerprint {
            return keychainDelegate!.assetKey(forFingerprint: fingerprint)
        }
        return nil
    }

    // MARK: local db functions
    func unlinkedAsset(withMD5Hash md5: Data, callback: @escaping (Asset?) -> Void) {
        assetController.unlinkedAsset(withMD5Hash: md5, callback: callback)
    }

    func `switch`(localIdentifier: String, fromAssetID oldAssetID: UUID, toAssetID newAssetID: UUID) {
        assetController.switch(localIdentifier: localIdentifier, fromAssetID: oldAssetID, toAssetID: newAssetID)
    }

    // MARK: disk functions
    func fileExists(at url: URL) -> Bool {
        assert(!Thread.isMainThread)

        let reachable = try? url.checkResourceIsReachable()
        return reachable ?? false
    }

    func write(_ data: Data, to url: URL) -> Bool {
        assert(!Thread.isMainThread)

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

        do {
            try FileManager.default.removeItem(at: url)
        } catch CocoaError.fileNoSuchFile {
        } catch {
            log.error("error deleting file: \(url.absoluteString), error: \(String(describing: error))")
            return false
        }
        return true
    }

    // https://stackoverflow.com/a/42935601/2728986
    func md5(ofFileAtURL url: URL) -> Data? {
        assert(!Thread.isMainThread)

        let bufferSize = 1024 * 1024
        do {
            // open file for reading
            let file = try FileHandle(forReadingFrom: url)
            defer {
                file.closeFile()
            }

            // create and initialize MD5 context
            var context = CC_MD5_CTX()
            CC_MD5_Init(&context)

            // read up to `bufferSize` bytes, until EOF is reached, and update MD5 context
            while autoreleasepool(invoking: {
                let data = file.readData(ofLength: bufferSize)
                if data.count > 0 {
                    data.withUnsafeBytes {
                        _ = CC_MD5_Update(&context, $0.baseAddress, numericCast(data.count))
                    }
                    return true // Continue
                } else {
                    return false // End of file
                }
            }) { }

            // compute the MD5 digest
            var digest: [UInt8] = Array(repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
            _ = CC_MD5_Final(&digest, &context)

            return Data(digest)
        } catch {
            log.error("cannot open file: \(String(describing: error))")
            return nil
        }
    }

    /*
        https://nshipster.com/image-resizing/#cgimagesourcecreatethumbnailatindex
        https://developer.apple.com/videos/play/wwdc2018/219/
     */
    func downsample(imageAt imageSourceURL: URL, originalSize size: CGSize, toScale scale: CGFloat, compress: Bool, destination imageDestinationURL: URL) -> Bool {
        let imageSourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary     // don't decode source image, just create CGImageSource that represents the data
        guard let imageSource = CGImageSourceCreateWithURL(imageSourceURL as CFURL, imageSourceOptions) else {
            assertionFailure()
            return false
        }

        let thumbnailOptions = [
            kCGImageSourceThumbnailMaxPixelSize: Swift.max(size.width, size.height) * scale,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: false      // don't decode destination thumbnail image – no need as we're writing it to disk
        ] as CFDictionary
        guard let scaledImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, thumbnailOptions as CFDictionary) else {
            assertionFailure("unable to create thumbnail image")
            return false
        }

        let imageDestinationAttempt = CGImageDestinationCreateWithURL(imageDestinationURL as CFURL, kUTTypeJPEG, 1, nil)
        if imageDestinationAttempt == nil {
            log.verbose("create parent directory and try again")    // e.g. asset ownerid folder
            do {
                try FileManager.default.createDirectory(at: imageDestinationURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
            } catch {
                log.error("error creating parent directory – directory: \(imageDestinationURL.deletingLastPathComponent()), error: \(String(describing: error))")
                return false
            }
        }
        guard let imageDestination = imageDestinationAttempt ?? CGImageDestinationCreateWithURL(imageDestinationURL as CFURL, kUTTypeJPEG, 1, nil) else {
            log.error("unable to create image destination - sourceURL: \(imageSourceURL), destinationURL: \(imageDestinationURL)")
            assertionFailure()
            return false
        }
        let imageDestinationOptions = compress ? [kCGImageDestinationLossyCompressionQuality as String: 0.0] as CFDictionary : nil  // maximum compression, if compression is used
        CGImageDestinationAddImage(imageDestination, scaledImage, imageDestinationOptions)

        return CGImageDestinationFinalize(imageDestination)
    }

    func compressVideo(atURL url: URL, callback: @escaping (URL?) -> Void) {
        let asset = AVAsset(url: url)
        let preset = AVAssetExportPresetLowQuality
        let uti: AVFileType = .mp4
        AVAssetExportSession.determineCompatibility(ofExportPreset: preset, with: asset, outputFileType: uti) { isCompatible in
            guard isCompatible else {
                self.log.error("export session incompatible - sourceURL: \(String(describing: url)), preset: \(preset), uti: \(String(describing: uti))")
                callback(nil)
                return
            }
            guard let exportSession = AVAssetExportSession(asset: asset, presetName: preset) else {
                callback(nil)
                return
            }
            guard let destinationURL = FileManager.default.uniqueTempFile(filename: url.deletingPathExtension().lastPathComponent, fileExtension: uti.fileExtension ?? "") else {
                callback(nil)
                return
            }
            exportSession.outputURL = destinationURL
            exportSession.outputFileType = uti
            exportSession.exportAsynchronously(completionHandler: { [unowned exportSession] in
                if case .completed = exportSession.status {
                    callback(destinationURL)
                } else {
                    self.log.error("sourceURL: \(String(describing: url)), destinationURL: \(String(describing: destinationURL)) - error: \(String(describing: exportSession.error))")
                    callback(nil)
                }
            })
        }
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
    func createOnServer(assets: [AssetManager.MutableAsset], callback: @escaping (Result<[String: Int], Error>) -> Void) {
        keychainQueue.async { [weak self] in
            guard let self = self else {
                return
            }
            let userKey = self.keychainDelegate!.primaryUserKey
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

    func writeOriginalToDB(assets: [AssetManager.MutableAsset], callback: @escaping ([String: Int]?) -> Void) {
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

    func deleteFromDB(assets: [AssetManager.MutableAsset], callback: @escaping ClosureBool) {
        webAPI.delete(assetIDs: assets.map{ $0.uuid.string }, callbackOn: .global()) { success in
            callback(success)
        }
    }
}

extension AssetManager: AssetOperationDelegate {
    func newAssetKey() -> CryptoPrivateKey {
        assert(.notOn(assetManagerQueue))
        return assetOperationDelegate.newAssetKey()
    }

    func key(for asset: AssetManager.MutableAsset) -> CryptoPrivateKey? {
        assert(.notOn(assetManagerQueue))
        return assetOperationDelegate.key(for: asset)
    }

    func unlinkedAsset(withMD5Hash md5: Data, callback: @escaping (Asset?) -> Void) {
        assetOperationDelegate.unlinkedAsset(withMD5Hash: md5, callback: callback)
    }

    func `switch`(localIdentifier: String, fromAssetID oldAssetID: UUID, toAssetID newAssetID: UUID) {
        assetOperationDelegate.switch(localIdentifier: localIdentifier, fromAssetID: oldAssetID, toAssetID: newAssetID)
    }

    func fileExists(at url: URL) -> Bool {
        assert(.notOn(assetManagerQueue))
        return assetOperationDelegate.fileExists(at: url)
    }

    func write(_ data: Data, to url: URL) -> Bool {
        assert(.notOn(assetManagerQueue))
        return assetOperationDelegate.write(data, to: url)
    }

    func load(_ url: URL) -> Data? {
        assert(.notOn(assetManagerQueue))
        return assetOperationDelegate.load(url)
    }

    @discardableResult func delete(resourceAt url: URL) -> Bool {
        assert(.notOn(assetManagerQueue))
        return assetOperationDelegate.delete(resourceAt: url)
    }

    func md5(ofFileAtURL url: URL) -> Data? {
        assert(.notOn(assetManagerQueue))
        return assetOperationDelegate.md5(ofFileAtURL: url)
    }

    func downsample(imageAt imageSourceURL: URL, originalSize size: CGSize, toScale scale: CGFloat, compress: Bool, destination imageDestinationURL: URL) -> Bool {
        return assetOperationDelegate.downsample(imageAt: imageSourceURL, originalSize: size, toScale: scale, compress: compress, destination: imageDestinationURL)
    }

    func compressVideo(atURL url: URL, callback: @escaping (URL?) -> Void) {
        assetOperationDelegate.compressVideo(atURL: url, callback: callback)
    }

    func upload(fileAtURL localURL: URL, transferPriority: DataManager.Priority, callback: @escaping (URL?) -> Void) {
        assetOperationDelegate.upload(fileAtURL: localURL, transferPriority: transferPriority, callback: callback)
    }

    func downloadFile(at source: URL, to destination: URL, priority: DataManager.Priority, callback: @escaping ClosureBool) {
        assetOperationDelegate.downloadFile(at: source, to: destination, priority: priority, callback: callback)
    }

    func createOnServer(assets: [AssetManager.MutableAsset], callback: @escaping (Result<[String : Int], Error>) -> Void) {
        assetOperationDelegate.createOnServer(assets: assets, callback: callback)
    }

    func writeOriginalToDB(assets: [AssetManager.MutableAsset], callback: @escaping ([String : Int]?) -> Void) {
        assetOperationDelegate.writeOriginalToDB(assets: assets, callback: callback)
    }

    func deleteFromDB(assets: [AssetManager.MutableAsset], callback: @escaping ClosureBool) {
        assetOperationDelegate.deleteFromDB(assets: assets, callback: { [weak self] (success: Bool) in
            self?.assetManagerQueue.async {
                callback(success)
            }
        })
    }
}
