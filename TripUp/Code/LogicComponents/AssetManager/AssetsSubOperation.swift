//
//  AssetSubOperationBatch.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 23/02/2021.
//  Copyright © 2021 Vinoth Ramiah. All rights reserved.
//

import Foundation
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
        let assets: [Asset]
        unowned let delegate: AssetOperationDelegate
        var result: ResultType = .failure(.notRun)
        let log = Logger.self

        init(assets: [Asset], stateDelegate: AssetOperationDelegate) {
            self.assets = assets
            self.delegate = stateDelegate
            super.init()
        }

        func dependenciesSucceeded() -> Bool {
            for dependency in dependencies {
                if let dependency = dependency as? AssetOperationResult {
                    guard case .success = dependency.result else {
                        return false
                    }
                }
            }
            return true
        }

        func finish(_ result: ResultType) {
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
    class OPGenerateEncryptionKey: AssetSubOperationBatch<MutableAsset> {
        override func main() {
            guard dependenciesSucceeded() else {
                finish()
                return
            }

            let dispatchGroup = DispatchGroup()
            for asset in assets {
                guard asset.fingerprint == nil else {
                    log.warning("\(asset.uuid.string): already has a key fingerprint assigned. Using existing key")
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

    class OPFetchingFromIOS: AssetSubOperationBatch<MutableAsset> {
        override func main() {
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

    class OPWritingLowToDB: AssetSubOperationBatch<MutableAsset> {
        override func main() {
            guard dependenciesSucceeded() else {
                finish()
                return
            }

            delegate.writeLowToDB(assets: assets) { success in
                if success {
                    self.finish(.success(nil))
                } else {
                    self.log.error("\(self.assets.map{ $0.uuid.string }): something went wrong with adding assets to db")
                    self.finish(.failure(.recoverable))
                }
            }
        }
    }

    class OPWritingOriginalToDB: AssetSubOperationBatch<MutableAsset> {
        override func main() {
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

    class OPDeletingFromDB: AssetSubOperationBatch<MutableAsset> {
        override func main() {
            guard dependenciesSucceeded() else {
                finish()
                return
            }

            delegate.deleteFromDB(assets: assets) { success in
                if success {
                    self.finish(.success(nil))
                } else {
                    self.log.error("\(self.assets.map{ $0.uuid.string }): something went wrong with deleting assets from server")
                    self.finish(.failure(.recoverable))
                }
            }
        }
    }
}

extension AssetManager {
    class OPCompressingData: AssetSubOperationBatch<MutablePhysicalAsset> {
        override func main() {
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
                guard let originalData = delegate.load(asset.logicalAsset.physicalAssets.original.localPath) else {
                    error = error ?? .recoverable
                    break
                }

                dispatchGroup.enter()
                DispatchQueue.global(qos: .utility).async {
                    defer {
                        dispatchGroup.leave()
                    }
                    guard !self.isCancelled else {
                        error = error ?? .notRun
                        return
                    }
                    if let compressedData = originalData.downsample(to: asset.pixelSize, scale: 0.5, compress: true) {
                        if !self.delegate.write(compressedData, to: asset.localPath) {
                            error = error ?? .recoverable
                        }
                    } else {
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
    }

    class OPEncryptingData: AssetSubOperationBatch<AssetManager.MutablePhysicalAsset> {
        override func main() {
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

    class OPUploadingData: AssetSubOperationBatch<AssetManager.MutablePhysicalAsset> {
        override func main() {
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
    class OPDownloadingData: AssetSubOperationBatch<AssetManager.MutablePhysicalAsset> {
        override func main() {
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

    class OPDecryptingData: AssetSubOperationBatch<AssetManager.MutablePhysicalAsset> {
        override func main() {
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
