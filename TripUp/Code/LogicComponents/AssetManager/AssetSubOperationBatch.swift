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
            let filename = "\(asset.uuid.string)_\(String(describing: asset.quality).lowercased())"
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
                guard !delegate.fileExists(at: asset.physicalAssets.original.localPath) || asset.md5 == nil else {
                    continue
                }

                guard let localIdentifier = asset.localIdentifier else {
                    log.error("\(asset.uuid.string): no localIdentifier found. Terminating...")
                    error = error ?? .fatal
                    return
                }

                dispatchGroup.enter()
                delegate.photoLibrary.fetchAsset(withLocalIdentifier: localIdentifier, callbackOn: .global(qos: .utility)) { phAsset in
                    guard !self.isCancelled else {
                        error = error ?? .notRun
                        dispatchGroup.leave()
                        return
                    }
                    guard let phAsset = phAsset else {
                        self.log.error("\(asset.uuid.string): unable to find PHAsset! Terminating - PHAssetID: \(String(describing: asset.localIdentifier))")
                        error = error ?? .fatal
                        dispatchGroup.leave()
                        return
                    }
                    guard let phAssetResource = self.delegate.photoLibrary.resource(forPHAsset: phAsset, type: asset.type) else {
                        self.log.error("\(asset.uuid.string): unable to find PHAssetResource! Terminating - PHAssetID: \(String(describing: asset.localIdentifier))")
                        error = error ?? .fatal
                        dispatchGroup.leave()
                        return
                    }
                    let uti = AVFileType(phAssetResource.uniformTypeIdentifier)
                    if uti.isCrossCompatible {
                        guard let tempURL = FileManager.default.createUniqueTempFile(filename: asset.uuid.string, fileExtension: uti.fileExtension) else {
                            error = error ?? .recoverable
                            dispatchGroup.leave()
                            return
                        }
                        self.delegate.photoLibrary.write(resource: phAssetResource, toURL: tempURL) { (success) in
                            guard success else {
                                error = error ?? .recoverable
                                dispatchGroup.leave()
                                return
                            }
                            self.join(asset: asset, toTempURL: tempURL, uti: uti) { (returnedError) in
                                error = error ?? returnedError
                                dispatchGroup.leave()
                            }
                        }
                    } else {
                        switch asset.type {
                        case .photo:
                            fatalError(asset.type.rawValue)  // TODO
                        case .video:
                            self.delegate.photoLibrary.transcodeVideoToMP4(forPHAsset: phAsset) { (output) in
                                guard let tempURL = output?.0, let uti = output?.1 else {
                                    error = error ?? .recoverable
                                    dispatchGroup.leave()
                                    return
                                }
                                self.join(asset: asset, toTempURL: tempURL, uti: uti) { (returnedError) in
                                    error = error ?? returnedError
                                    dispatchGroup.leave()
                                }
                            }
                        case .audio, .unknown:
                            fatalError()
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

        private func join(asset: MutableAsset, toTempURL tempURL: URL, uti: AVFileType, callback: @escaping (AssetSubOperationError?) -> Void) {
            guard let md5 = delegate.md5(ofFileAtURL: tempURL) else {
                callback(.recoverable)
                return
            }
            delegate.unlinkedAsset(withMD5Hash: md5) { candidateAsset in
                if let candidateAsset = candidateAsset {
                    self.delegate.save(localIdentifier: asset.localIdentifier, forAsset: candidateAsset)
                    self.log.info("\(asset.uuid.string): existing asset md5 match found. Linked localIdentifier and terminating this asset – existingAssetID: \(candidateAsset.uuid.string), PHAssetID: \(String(describing: asset.localIdentifier))")
                    try? FileManager.default.removeItem(at: tempURL)
                    callback(.fatal)    // terminate this asset, as we've linked the image data to another asset
                } else {
                    let url = asset.physicalAssets.original.localPath.deletingPathExtension().appendingPathExtension(uti.fileExtension ?? "")
                    if (try? FileManager.default.moveItem(at: tempURL, to: url)) != nil {
                        asset.originalUTI = uti
                        asset.md5 = md5
                        callback(nil)
                    } else {
                        callback(.recoverable)
                    }
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

                dispatchGroup.enter()
                DispatchQueue.global(qos: .utility).async {
                    guard !self.isCancelled else {
                        error = error ?? .notRun
                        dispatchGroup.leave()
                        return
                    }

                    let originalPath = asset.logicalAsset.physicalAssets.original.localPath
                    switch asset.logicalAsset.type {
                    case .photo:
                        if !self.delegate.downsample(imageAt: originalPath, originalSize: asset.pixelSize, toScale: 0.5, compress: true, destination: asset.localPath) {
                            self.log.error("\(asset.uuid.string): failed to compress original data")
                            error = error ?? .recoverable
                        }
                        dispatchGroup.leave()
                    case .video:
                        self.delegate.photoLibrary.compressVideo(atURL: originalPath) { (tempURL) in
                            if let tempURL = tempURL {
                                if (try? FileManager.default.moveItem(at: tempURL, to: asset.localPath)) == nil {
                                    try? FileManager.default.removeItem(at: tempURL)
                                    error = error ?? .recoverable
                                }
                            } else {
                                self.log.error("\(asset.uuid.string): failed to compress video data")
                                error = error ?? .recoverable
                            }
                            dispatchGroup.leave()
                        }
                    case .audio, .unknown:
                        fatalError()
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
