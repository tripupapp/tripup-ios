//
//  AssetSubOperationBatch.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 23/02/2021.
//  Copyright © 2021 Vinoth Ramiah. All rights reserved.
//

import Foundation
import ImageIO
import MobileCoreServices.UTCoreTypes
import struct AVFoundation.AVFileType

protocol AssetOperationResult {
    typealias ResultType = Result<Any?, AssetManager.AssetSubOperationError>
    var result: ResultType { get }
}

extension AssetManager {
    enum AssetSubOperationError: Error {
        case notRun
        case recoverable
        case fatal
    }

    class AssetSubOperationBatch<Asset: MutableAssetProtocol>: AsynchronousOperation {
        var result: ResultType = .failure(.notRun)

        fileprivate unowned let delegate: AssetOperationDelegate
        fileprivate let assets: [Asset]
        fileprivate let log = Logger.self

        init(assets: [Asset], delegate: AssetOperationDelegate) {
            self.assets = assets
            self.delegate = delegate
            super.init()
        }

        fileprivate func dependenciesSucceeded() -> Bool {
            for dependency in dependencies {
                if let dependency = dependency as? AssetOperationResult {
                    guard case .success = dependency.result else {
                        return false
                    }
                }
            }
            return true
        }

        fileprivate func finish(_ result: ResultType) {
            self.result = result
            super.finish()
        }

        fileprivate func tempURLForEncryptedItem(physicalAsset asset: AssetManager.MutablePhysicalAsset) -> URL {
            let filename = "\(asset.filename)_\(String(describing: asset.quality).lowercased())"
            return Globals.Directories.tmp.appendingPathComponent(filename, isDirectory: false)
        }
    }
}

extension AssetManager.AssetSubOperationBatch: AssetOperationResult {}

extension AssetManager {
    class GenerateEncryptionKey: AssetSubOperationBatch<MutableAsset> {
        override func main() {
            super.main()
            guard dependenciesSucceeded() else {
                finish()
                return
            }

            let dispatchGroup = DispatchGroup()
            for asset in assets {
                guard asset.fingerprint == nil else {
                    log.debug("\(asset.uuid.string): already has a key fingerprint assigned. Using existing key")
                    continue
                }
                dispatchGroup.enter()
                delegate.keychainQueue.async(flags: .barrier) {
                    let key = self.delegate.newAssetKey()
                    asset.fingerprint = key.fingerprint
                    dispatchGroup.leave()
                }
            }

            dispatchGroup.notify(queue: .global(qos: .utility)) {
                self.finish(.success(nil))
            }
        }
    }

    class FetchFromIOS: AssetSubOperationBatch<MutableAsset> {
        override func main() {
            super.main()
            guard dependenciesSucceeded() else {
                finish()
                return
            }

            var error: AssetSubOperationError?
            let dispatchGroup = DispatchGroup()

            for asset in assets {
                guard !delegate.fileExists(at: asset.physicalAssets.original.localPath) else {
                    continue
                }

                guard let localID = asset.localIdentifier else {
                    log.error("\(asset.uuid.string): no localIdentifier found. Terminating...")
                    error = error ?? .fatal
                    break
                }

                dispatchGroup.enter()
                delegate.requestIOSAsset(withLocalID: localID, callbackOn: .global(qos: .utility)) { (iosAsset) in
                    guard let iosAsset = iosAsset else {
                        self.log.error("\(asset.uuid.string): unable to find PHAsset! Terminating - PHAssetID: \(String(describing: asset.localIdentifier))")
                        error = error ?? .fatal
                        dispatchGroup.leave()
                        return
                    }

                    guard !self.isCancelled else {
                        error = error ?? .notRun
                        dispatchGroup.leave()
                        return
                    }

                    let (data, imageUTI) = self.delegate.requestImageDataFromIOS(with: iosAsset)
                    guard let imageData = data else {
                        self.log.error("\(asset.uuid.string): failed to retrieve PHAsset data from PHImageManager. Terminating.... – PHAssetID: \(localID)")
                        error = error ?? .fatal
                        dispatchGroup.leave()
                        return
                    }

                    // duplicate detection, based on md5 of data
                    let md5 = imageData.md5()
                    self.delegate.unlinkedAsset(withMD5Hash: md5) { candidateAsset in
                        if let candidateAsset = candidateAsset {
                            self.delegate.save(localIdentifier: localID, forAsset: candidateAsset)
                            self.log.info("\(asset.uuid.string): existing asset md5 match found. Linked localIdentifier and terminating this asset – existingAssetID: \(candidateAsset.uuid.string), PHAssetID: \(localID)")
                            error = error ?? .fatal     // terminate this asset, as we've linked the image data to another asset
                        } else {
                            if self.delegate.write(imageData, to: asset.physicalAssets.original.localPath) {
                                asset.md5 = md5
                                if let imageUTI = imageUTI {
                                    asset.originalUTI = AVFileType(imageUTI)
                                }
                            } else {
                                error = error ?? .recoverable
                            }
                        }
                        dispatchGroup.leave()
                    }
                }
            }

            dispatchGroup.notify(queue: .global(qos: .utility)) {
                if let error = error {
                    self.finish(.failure(error))
                } else {
                    self.finish(.success(nil))
                }
            }
        }
    }

    class CreateOnServer: AssetSubOperationBatch<MutableAsset> {
        override func main() {
            super.main()
            guard dependenciesSucceeded() else {
                finish()
                return
            }

            delegate.createOnServer(assets: assets) { result in
                switch result {
                case .success(let cloudFilesizes):
                    for asset in self.assets {
                        if let filesize = cloudFilesizes[asset.uuid.string] {
                            asset.cloudFilesize = UInt64(filesize)
                            asset.imported = true
                            self.delegate.delete(resourceAt: asset.physicalAssets.original.localPath)
                        }
                    }
                    self.finish(.success(nil))
                case .failure(let error):
                    self.log.error("\(self.assets.map{ $0.uuid.string }): \(String(describing: error))")
                    self.finish(.failure(.recoverable))
                }
            }
        }
    }

    class WriteOriginalToDB: AssetSubOperationBatch<MutableAsset> {
        override func main() {
            super.main()
            guard dependenciesSucceeded() else {
                finish()
                return
            }

            delegate.writeOriginalToDB(assets: assets) { (cloudFilesizes) in
                if let cloudFilesizes = cloudFilesizes {
                    for asset in self.assets {
                        if let filesize = cloudFilesizes[asset.uuid.string] {
                            asset.cloudFilesize = UInt64(filesize)
                        } else {
                            assert(asset.cloudFilesize != 0)
                        }
                        asset.imported = true
                        self.delegate.delete(resourceAt: asset.physicalAssets.original.localPath)
                    }
                    self.finish(.success(nil))
                } else {
                    self.log.error("\(self.assets.map{ $0.uuid.string }): something went wrong with upating assets with original quality")
                    self.finish(.failure(.recoverable))
                }
            }
        }
    }

    class DeleteFromDB: AssetSubOperationBatch<MutableAsset> {
        override func main() {
            super.main()
            guard dependenciesSucceeded() else {
                finish()
                return
            }

            let assetsToDelete = assets.filter{ $0.physicalAssets.low.remotePath != nil || $0.physicalAssets.original.remotePath != nil }
            guard assetsToDelete.isNotEmpty else {
                finish(.success(nil))
                return
            }
            delegate.deleteFromDB(assets: assetsToDelete) { success in
                if success {
                    for asset in assetsToDelete {
                        asset.physicalAssets.low.remotePath = nil
                        asset.physicalAssets.original.remotePath = nil
                    }
                    self.finish(.success(nil))
                } else {
                    self.log.error("\(assetsToDelete.map{ $0.uuid.string }): something went wrong with deleting assets from server")
                    self.finish(.failure(.recoverable))
                }
            }
        }
    }
}

extension AssetManager {
    class CompressData: AssetSubOperationBatch<MutablePhysicalAsset> {
        override func main() {
            super.main()
            guard dependenciesSucceeded() else {
                finish()
                return
            }

            var error: AssetSubOperationError?
            let dispatchGroup = DispatchGroup()

            for asset in assets {
                precondition(asset.quality == .low)

                guard !delegate.fileExists(at: asset.localPath) else {
                    continue
                }
//                NOTE: using ios for low quality image generation seems faster, but less "correct" – an image can be deleted from user library after import has started
//                delegate.requestImageThumbnailFromIOS(assetID: asset.logicalAsset.iosAssetID!, size: asset.pixelSize, scale: 0.5) { [weak self, unowned asset = asset] (compressedData) in
//                    guard let self = self, let delegate = self.delegate else { return }
//                    if let compressedData = compressedData {
//                        if delegate.write(compressedData, to: asset.localPath) {
//                            delegate.assetManagerQueue.async { [weak self] in
//                                guard let self = self else { return }
//                                self.stateMachine?.enter(EncryptingData.self)
//                                self.delegate?.notify(of: .diskWriteDone(self.asset))
//                            }
//                        } else {
//                            delegate.assetManagerQueue.async { [weak self] in
//                                guard let self = self else { return }
//                                self.stateMachine?.enter(RecoverableError<AssetManager.MutablePhysicalAsset>.self)
//                                self.delegate?.notify(of: .diskWriteError(self.asset))
//                            }
//                        }
//                    } else {
//                        self.log.error("\(asset.uuid.string): failed to compress original data")
//                        delegate.assetManagerQueue.async { [weak self] in
//                            self?.stateMachine?.enter(RecoverableError<AssetManager.MutablePhysicalAsset>.self)
//                        }
//                    }
//                }

                dispatchGroup.enter()
                DispatchQueue.global(qos: .utility).async {
                    defer {
                        dispatchGroup.leave()
                    }
                    guard !self.isCancelled else {
                        error = error ?? .notRun
                        return
                    }

                    let originalPath = asset.logicalAsset.physicalAssets.original.localPath
                    if !self.downsample(imageAt: originalPath, originalSize: asset.pixelSize, toScale: 0.5, compress: true, destination: asset.localPath) {
                        self.log.error("\(asset.uuid.string): failed to compress original data")
                        error = error ?? .recoverable
                    }
                }
            }

            dispatchGroup.notify(queue: .global(qos: .utility)) {
                if let error = error {
                    self.finish(.failure(error))
                } else {
                    self.finish(.success(nil))
                }
            }
        }

        /*
            https://nshipster.com/image-resizing/#cgimagesourcecreatethumbnailatindex
            https://developer.apple.com/videos/play/wwdc2018/219/
         */
        private func downsample(imageAt imageSourceURL: URL, originalSize size: CGSize, toScale scale: CGFloat, compress: Bool, destination imageDestinationURL: URL) -> Bool {
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
    }

    class EncryptData: AssetSubOperationBatch<AssetManager.MutablePhysicalAsset> {
        override func main() {
            super.main()
            guard dependenciesSucceeded() else {
                finish()
                return
            }

            var error: AssetSubOperationError?
            let dispatchGroup = DispatchGroup()

            for asset in assets {
                guard asset.remotePath == nil else {
                    continue
                }
                guard let data = delegate.load(asset.localPath) else {
                    error = error ?? .recoverable
                    break
                }

                dispatchGroup.enter()
                delegate.keychainQueue.async {
                    guard let assetKey = self.delegate.key(for: asset.logicalAsset) else {
                        error = error ?? .recoverable
                        dispatchGroup.leave()
                        return
                    }
                    DispatchQueue.global(qos: .utility).async {
                        // must drain autoreleasepool after each encrypt/decrypt, because Crypto PGP framework uses NSData. Without this, memory usage will accumulate over time (memory leak)
                        autoreleasepool {
                            defer {
                                dispatchGroup.leave()
                            }
                            guard !self.isCancelled else {
                                error = error ?? .notRun
                                return
                            }

                            let encryptedData = assetKey.encrypt(data)

                            if !self.delegate.write(encryptedData, to: self.tempURLForEncryptedItem(physicalAsset: asset)) {
                                self.log.error("\(asset.uuid.string): failed to write encrypted data")
                                error = error ?? .recoverable
                            }
                        }
                    }
                }
            }

            dispatchGroup.notify(queue: .global(qos: .utility)) {
                if let error = error {
                    self.finish(.failure(error))
                } else {
                    self.finish(.success(nil))
                }
            }
        }
    }

    class UploadData: AssetSubOperationBatch<AssetManager.MutablePhysicalAsset> {
        override func main() {
            super.main()
            guard dependenciesSucceeded() else {
                finish()
                return
            }

            var error: AssetSubOperationError?
            let dispatchGroup = DispatchGroup()

            for asset in assets {
                guard asset.remotePath == nil else {
                    continue
                }

                let fileSource = tempURLForEncryptedItem(physicalAsset: asset)
                guard delegate.fileExists(at: fileSource) else {
                    error = error ?? .notRun
                    break
                }

                // if other asset quality has already uploaded, upload this asset quality with higher priority
                let oppositeQualityRemotePath: URL? = asset.quality == .low ? asset.logicalAsset.physicalAssets.original.remotePath : asset.logicalAsset.physicalAssets.low.remotePath
                let transferPriority: DataManager.Priority = oppositeQualityRemotePath == nil ? .low : .high

                dispatchGroup.enter()
                delegate.upload(fileAtURL: fileSource, transferPriority: transferPriority) { remoteURL in
                    defer {
                        dispatchGroup.leave()
                    }
                    if let remoteURL = remoteURL {
                        asset.remotePath = remoteURL
                        self.delegate.delete(resourceAt: fileSource)
                    } else {
                        self.log.error("\(asset.uuid.string): failed to upload file – sourceFilePath: \(String(describing: fileSource.absoluteString)), quality: \(asset.quality)")
                        error = error ?? .recoverable
                    }
                }
            }

            dispatchGroup.notify(queue: .global(qos: .utility)) {
                if let error = error {
                    self.finish(.failure(error))
                } else {
                    self.finish(.success(nil))
                }
            }
        }
    }
}

extension AssetManager {
    class DownloadData: AssetSubOperationBatch<AssetManager.MutablePhysicalAsset> {
        override func main() {
            super.main()
            guard dependenciesSucceeded() else {
                finish()
                return
            }

            var error: AssetSubOperationError?
            let dispatchGroup = DispatchGroup()

            for asset in assets {
                guard !delegate.fileExists(at: asset.localPath) else {
                    continue
                }
                guard let downloadURL = asset.remotePath else {
                    log.error("\(asset.uuid.string): no download url set")
                    error = error ?? .fatal
                    break
                }

                let tempURL = tempURLForEncryptedItem(physicalAsset: asset)
                dispatchGroup.enter()
                delegate.downloadFile(at: downloadURL, to: tempURL, priority: .high) { success in
                    defer {
                        dispatchGroup.leave()
                    }
                    if !success {
                        self.log.error("\(asset.uuid.string): failed to download file – url: \(String(describing: downloadURL)), destination: \(String(describing: tempURL))")
                        error = error ?? .recoverable
                    }
                }
            }

            dispatchGroup.notify(queue: .global(qos: .utility)) {
                if let error = error {
                    self.finish(.failure(error))
                } else {
                    self.finish(.success(nil))
                }
            }
        }
    }

    class DecryptData: AssetSubOperationBatch<AssetManager.MutablePhysicalAsset> {
        override func main() {
            super.main()
            guard dependenciesSucceeded() else {
                finish()
                return
            }

            var error: AssetSubOperationError?
            let dispatchGroup = DispatchGroup()

            for asset in assets {
                guard !delegate.fileExists(at: asset.localPath) else {
                    continue
                }

                let fileSource = tempURLForEncryptedItem(physicalAsset: asset)
                guard let encryptedData = delegate.load(fileSource), let assetKey = delegate.key(for: asset.logicalAsset) else {
                    log.error("\(asset.uuid.string): preconditions failed")
                    error = error ?? .recoverable
                    break
                }

                dispatchGroup.enter()
                DispatchQueue.global(qos: .utility).async {
                    // must drain autoreleasepool after each encrypt/decrypt, because Crypto PGP framework uses NSData. Without this, memory usage will accumulate over time (memory leak)
                    autoreleasepool {
                        defer {
                            dispatchGroup.leave()
                        }
                        guard let data = try? assetKey.decrypt(encryptedData) else {
                            self.log.error("\(asset.uuid.string): failed to decrypt data")
                            error = error ?? .recoverable
                            return
                        }
                        if self.delegate.write(data, to: asset.localPath) {
                            self.delegate.delete(resourceAt: fileSource)
                        } else {
                            self.log.error("\(asset.uuid.string): failed to write decrypted data to disk")
                            error = error ?? .recoverable
                        }
                    }
                }
            }

            dispatchGroup.notify(queue: .global(qos: .utility)) {
                if let error = error {
                    self.finish(.failure(error))
                } else {
                    self.finish(.success(nil))
                }
            }
        }
    }
}
