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
    var fatalAssets: Set<AssetManager.MutableAsset> { get }
}

extension AssetManager {
    enum AssetSubOperationError: Error {
        case notRun
        case recoverable
        case fatal
    }

    class AssetSubOperationBatch<Asset: MutableAssetProtocol>: AsynchronousOperation {
        private(set) var result: ResultType = .failure(.notRun)
        private(set) var fatalAssets = Set<AssetManager.MutableAsset>()

        fileprivate unowned let delegate: AssetOperationDelegate
        fileprivate let assets: [Asset]
        fileprivate let log = Logger.self
        private let queue = DispatchQueue(label: String(describing: self), qos: .utility, target: DispatchQueue.global(qos: .utility))
        private var error: AssetSubOperationError?

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

        override func finish() {
            queue.async { [weak self] in
                if let error = self?.error {
                    self?.result = .failure(error)
                } else {
                    self?.result = .success(nil)
                }
                self?.super_finish()
            }
        }

        // workaround for calling super from closure: https://github.com/lionheart/openradar-mirror/issues/6765#issuecomment-247612381
        private func super_finish() {
            super.finish()
        }

        func set(error: AssetSubOperationError, addToFatalSet fatalAsset: AssetManager.MutableAsset? = nil) {
            queue.async { [weak self] in
                if let self = self {
                    if self.error != .fatal {
                        self.error = error
                    }
                    if let fatalAsset = fatalAsset {
                        self.fatalAssets.insert(fatalAsset)
                    }
                }
            }
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
                set(error: .notRun)
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
                self.finish()
            }
        }
    }

    class FetchFromIOS: AssetSubOperationBatch<MutableAsset> {
        override func main() {
            super.main()
            guard dependenciesSucceeded() else {
                set(error: .notRun)
                finish()
                return
            }

            let dispatchGroup = DispatchGroup()
            for asset in assets {
                guard !delegate.fileExists(at: asset.physicalAssets.original.localPath) || asset.md5 == nil || asset.originalUTI == nil else {
                    continue
                }

                guard let localIdentifier = asset.localIdentifier else {
                    log.error("\(asset.uuid.string): no localIdentifier found. Terminating...")
                    set(error: .fatal, addToFatalSet: asset)
                    continue
                }

                dispatchGroup.enter()
                delegate.photoLibrary.fetchAsset(withLocalIdentifier: localIdentifier, callbackOn: .global(qos: .utility)) { phAsset in
                    guard !self.isCancelled else {
                        self.set(error: .recoverable)
                        dispatchGroup.leave()
                        return
                    }
                    guard let phAsset = phAsset else {
                        self.log.error("\(asset.uuid.string): unable to find PHAsset! Terminating - PHAssetID: \(String(describing: asset.localIdentifier))")
                        self.set(error: .fatal, addToFatalSet: asset)
                        dispatchGroup.leave()
                        return
                    }
                    guard let phAssetResource = self.delegate.photoLibrary.resource(forPHAsset: phAsset, type: asset.type) else {
                        self.log.error("\(asset.uuid.string): unable to find PHAssetResource! Terminating - PHAssetID: \(String(describing: asset.localIdentifier))")
                        self.set(error: .fatal, addToFatalSet: asset)
                        dispatchGroup.leave()
                        return
                    }
                    let originalFilename = phAssetResource.originalFilename
                    let uti = AVFileType(phAssetResource.uniformTypeIdentifier)
                    guard let tempURL = FileManager.default.uniqueTempFile(filename: asset.uuid.string, fileExtension: uti.fileExtension) else {
                        self.set(error: .recoverable)
                        dispatchGroup.leave()
                        return
                    }
                    self.delegate.photoLibrary.write(resource: phAssetResource, toURL: tempURL) { (success) in
                        guard success else {
                            self.set(error: .recoverable)
                            dispatchGroup.leave()
                            return
                        }
                        guard let md5 = self.delegate.md5(ofFileAtURL: tempURL) else {
                            self.log.error("error calculating md5 - assetID: \(asset.uuid.string), inputURL: \(String(describing: tempURL))")
                            self.set(error: .recoverable)
                            dispatchGroup.leave()
                            return
                        }
                        self.delegate.unlinkedAsset(withMD5Hash: md5) { candidateAsset in
                            if let candidateAsset = candidateAsset {
                                // verify metadata and update server asset with local metadata if necessary
                                self.verifyMetadata(forAsset: candidateAsset, originalFilename: originalFilename) { (verified) in
                                    if verified {
                                        self.delegate.switch(localIdentifier: localIdentifier, fromAssetID: asset.uuid, toAssetID: candidateAsset.uuid)
                                        self.log.info("\(asset.uuid.string): existing asset md5 match found. Linked localIdentifier and terminating this asset – existingAssetID: \(candidateAsset.uuid.string), PHAssetID: \(String(describing: asset.localIdentifier))")
                                        self.set(error: .fatal, addToFatalSet: asset)   // terminate this asset, as we've linked the image data to another asset
                                    } else {
                                        self.set(error: .recoverable)
                                    }
                                    try? FileManager.default.removeItem(at: tempURL)
                                    dispatchGroup.leave()
                                }
                            } else {
                                asset.md5 = md5
                                asset.originalFilename = originalFilename
                                asset.originalUTI = uti
                                let url = asset.physicalAssets.original.localPath.deletingPathExtension().appendingPathExtension(uti.fileExtension ?? "")
                                if (try? FileManager.default.moveItem(at: tempURL, to: url, createIntermediateDirectories: true, overwrite: true)) == nil {
                                    self.log.error("failed to move file - assetID: \(asset.uuid.string), currentURL: \(String(describing: tempURL)), destinationURL: \(String(describing: url))")
                                    try? FileManager.default.removeItem(at: tempURL)
                                    self.set(error: .recoverable)
                                }
                                dispatchGroup.leave()
                            }
                        }
                    }
                }
            }

            dispatchGroup.notify(queue: .global(qos: .utility)) {
                self.finish()
            }
        }

        private func verifyMetadata(forAsset asset: AssetManager.MutableAsset, originalFilename: String, callback: @escaping (Bool) -> Void) {
            if asset.originalFilename != originalFilename {
                delegate.updateOnDB(asset: asset, originalFilename: originalFilename) { (success) in
                    if success {
                        asset.originalFilename = originalFilename
                    }
                    callback(success)
                }
            } else {
                callback(true)
            }
        }
    }

    class CreateOnServer: AssetSubOperationBatch<MutableAsset> {
        override func main() {
            super.main()
            guard dependenciesSucceeded() else {
                set(error: .notRun)
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
                    self.finish()
                case .failure(let error):
                    self.log.error("\(self.assets.map{ $0.uuid.string }): \(String(describing: error))")
                    self.set(error: .recoverable)
                    self.finish()
                }
            }
        }
    }

    class WriteOriginalToDB: AssetSubOperationBatch<MutableAsset> {
        override func main() {
            super.main()
            guard dependenciesSucceeded() else {
                set(error: .notRun)
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
                    self.finish()
                } else {
                    self.log.error("\(self.assets.map{ $0.uuid.string }): something went wrong with upating assets with original quality")
                    self.set(error: .recoverable)
                    self.finish()
                }
            }
        }
    }

    class DeleteFromDB: AssetSubOperationBatch<MutableAsset> {
        override func main() {
            super.main()
            guard dependenciesSucceeded() else {
                set(error: .notRun)
                finish()
                return
            }

            let assetsToDelete = assets.filter{ $0.physicalAssets.low.remotePath != nil || $0.physicalAssets.original.remotePath != nil }
            guard assetsToDelete.isNotEmpty else {
                finish()
                return
            }
            delegate.deleteFromDB(assets: assetsToDelete) { success in
                if success {
                    for asset in assetsToDelete {
                        asset.physicalAssets.low.remotePath = nil
                        asset.physicalAssets.original.remotePath = nil
                    }
                    self.finish()
                } else {
                    self.log.error("\(assetsToDelete.map{ $0.uuid.string }): something went wrong with deleting assets from server")
                    self.set(error: .recoverable)
                    self.finish()
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
                set(error: .notRun)
                finish()
                return
            }

            let dispatchGroup = DispatchGroup()
            for asset in assets {
                precondition(asset.quality == .low)

                guard !delegate.fileExists(at: asset.localPath) else {
                    continue
                }

                dispatchGroup.enter()
                DispatchQueue.global(qos: .utility).async {
                    guard !self.isCancelled else {
                        self.set(error: .recoverable)
                        dispatchGroup.leave()
                        return
                    }

                    let originalPath = asset.logicalAsset.physicalAssets.original.localPath
                    switch asset.logicalAsset.type {
                    case .photo:
                        if !self.delegate.downsample(imageAt: originalPath, originalSize: asset.pixelSize, toScale: 0.5, compress: true, destination: asset.localPath) {
                            self.log.error("\(asset.uuid.string): failed to compress original data")
                            self.set(error: .recoverable)
                        }
                        dispatchGroup.leave()
                    case .video:
                        self.delegate.compressVideo(atURL: originalPath) { (tempURL) in
                            if let tempURL = tempURL {
                                if (try? FileManager.default.moveItem(at: tempURL, to: asset.localPath, createIntermediateDirectories: true, overwrite: true)) == nil {
                                    try? FileManager.default.removeItem(at: tempURL)
                                    self.set(error: .recoverable)
                                }
                            } else {
                                self.log.error("\(asset.uuid.string): failed to compress video data")
                                self.set(error: .recoverable)
                            }
                            dispatchGroup.leave()
                        }
                    case .audio, .unknown:
                        fatalError()
                    }

                }
            }

            dispatchGroup.notify(queue: .global(qos: .utility)) {
                self.finish()
            }
        }
    }

    class EncryptData: AssetSubOperationBatch<AssetManager.MutablePhysicalAsset> {
        override func main() {
            super.main()
            guard dependenciesSucceeded() else {
                set(error: .notRun)
                finish()
                return
            }

            let dispatchGroup = DispatchGroup()
            for asset in assets {
                guard asset.remotePath == nil else {
                    continue
                }

                dispatchGroup.enter()
                switch asset.logicalAsset.type {
                case .photo:
                    encryptPhoto(asset: asset) { (returnedError) in
                        if let error = returnedError {
                            self.set(error: error)
                        }
                        dispatchGroup.leave()
                    }
                case .video:
                    encryptVideo(asset: asset) { (returnedError) in
                        if let error = returnedError {
                            self.set(error: error)
                        }
                        dispatchGroup.leave()
                    }
                case .audio, .unknown:
                    fatalError()
                }
            }

            dispatchGroup.notify(queue: .global(qos: .utility)) {
                self.finish()
            }
        }

        // TODO: make default way for all types
        private func encryptVideo(asset: MutablePhysicalAsset, callback: @escaping (AssetSubOperationError?) -> Void) {
            delegate.keychainQueue.async { [weak self] in
                guard let self = self, let assetKey = self.delegate.key(for: asset.logicalAsset) else {
                    callback(.recoverable)
                    return
                }
                DispatchQueue.global(qos: .utility).async {
                    // 500 KB chunk size for videos
                    guard let encryptedURL = assetKey.encrypt(fileAtURL: asset.localPath, chunkSize: 500000, outputFilename: asset.uuid.string) else {
                        callback(.recoverable)
                        return
                    }
                    do {
                        try FileManager.default.moveItem(at: encryptedURL, to: self.tempURLForEncryptedItem(physicalAsset: asset), createIntermediateDirectories: true, overwrite: true)
                        callback(nil)
                    } catch {
                        self.log.error(String(describing: error))
                        assertionFailure()
                        try? FileManager.default.removeItem(at: encryptedURL)
                        callback(.recoverable)
                    }
                }
            }
        }

        private func encryptPhoto(asset: MutablePhysicalAsset, callback: @escaping (AssetSubOperationError?) -> Void) {
            guard let data = delegate.load(asset.localPath) else {
                callback(.recoverable)
                return
            }
            delegate.keychainQueue.async {
                guard let assetKey = self.delegate.key(for: asset.logicalAsset) else {
                    callback(.recoverable)
                    return
                }
                DispatchQueue.global(qos: .utility).async {
                    // must drain autoreleasepool after each encrypt/decrypt, because Crypto PGP framework uses NSData. Without this, memory usage will accumulate over time (memory leak)
                    autoreleasepool {
                        guard !self.isCancelled else {
                            callback(.notRun)
                            return
                        }

                        let encryptedData = assetKey.encrypt(data)

                        if !self.delegate.write(encryptedData, to: self.tempURLForEncryptedItem(physicalAsset: asset)) {
                            self.log.error("\(asset.uuid.string): failed to write encrypted data")
                            callback(.recoverable)
                        } else {
                            callback(nil)
                        }
                    }
                }
            }
        }
    }

    class UploadData: AssetSubOperationBatch<AssetManager.MutablePhysicalAsset> {
        override func main() {
            super.main()
            guard dependenciesSucceeded() else {
                set(error: .notRun)
                finish()
                return
            }

            let dispatchGroup = DispatchGroup()
            for asset in assets {
                guard asset.remotePath == nil else {
                    continue
                }

                let fileSource = tempURLForEncryptedItem(physicalAsset: asset)
                guard delegate.fileExists(at: fileSource) else {
                    set(error: .recoverable)
                    continue
                }

                // if other asset quality has already uploaded, upload this asset quality with higher priority
                let oppositeQualityRemotePath: URL? = asset.quality == .low ? asset.logicalAsset.physicalAssets.original.remotePath : asset.logicalAsset.physicalAssets.low.remotePath
                let transferPriority: DataManager.Priority = oppositeQualityRemotePath == nil ? .low : .high

                dispatchGroup.enter()
                delegate.upload(fileAtURL: fileSource, transferPriority: transferPriority) { remoteURL in
                    if let remoteURL = remoteURL {
                        asset.remotePath = remoteURL
                        self.delegate.delete(resourceAt: fileSource)
                    } else {
                        self.log.error("\(asset.uuid.string): failed to upload file – sourceFilePath: \(String(describing: fileSource.absoluteString)), quality: \(asset.quality)")
                        self.set(error: .recoverable)
                    }
                    dispatchGroup.leave()
                }
            }

            dispatchGroup.notify(queue: .global(qos: .utility)) {
                self.finish()
            }
        }
    }
}

extension AssetManager {
    class DownloadData: AssetSubOperationBatch<AssetManager.MutablePhysicalAsset> {
        override func main() {
            super.main()
            guard dependenciesSucceeded() else {
                set(error: .notRun)
                finish()
                return
            }

            let dispatchGroup = DispatchGroup()
            for asset in assets {
                guard !delegate.fileExists(at: asset.localPath) else {
                    continue
                }
                guard let downloadURL = asset.remotePath else {
                    log.error("\(asset.uuid.string): no download url set")
                    set(error: .fatal, addToFatalSet: asset.logicalAsset)
                    continue
                }

                let tempURL = tempURLForEncryptedItem(physicalAsset: asset)
                dispatchGroup.enter()
                delegate.downloadFile(at: downloadURL, to: tempURL, priority: .high) { success in
                    if !success {
                        self.log.error("\(asset.uuid.string): failed to download file – url: \(String(describing: downloadURL)), destination: \(String(describing: tempURL))")
                        self.set(error: .recoverable)
                    }
                    dispatchGroup.leave()
                }
            }

            dispatchGroup.notify(queue: .global(qos: .utility)) {
                self.finish()
            }
        }
    }

    class DecryptData: AssetSubOperationBatch<AssetManager.MutablePhysicalAsset> {
        override func main() {
            super.main()
            guard dependenciesSucceeded() else {
                set(error: .notRun)
                finish()
                return
            }

            let dispatchGroup = DispatchGroup()
            for asset in assets {
                guard !delegate.fileExists(at: asset.localPath) else {
                    continue
                }

                let fileSource = tempURLForEncryptedItem(physicalAsset: asset)
                dispatchGroup.enter()
                switch asset.logicalAsset.type {
                case .photo:
                    decryptPhoto(asset: asset, fileSource: fileSource) { (returnedError) in
                        try? FileManager.default.removeItem(at: fileSource)
                        if let error = returnedError {
                            self.set(error: error)
                        }
                        dispatchGroup.leave()
                    }
                case .video:
                    decryptVideo(asset: asset, fileSource: fileSource) { (returnedError) in
                        try? FileManager.default.removeItem(at: fileSource)
                        if let error = returnedError {
                            self.set(error: error)
                        }
                        dispatchGroup.leave()
                    }
                case .audio, .unknown:
                    fatalError()
                }
            }

            dispatchGroup.notify(queue: .global(qos: .utility)) {
                self.finish()
            }
        }

        // TODO: make default way for all file types
        private func decryptVideo(asset: MutablePhysicalAsset, fileSource: URL, callback: @escaping (AssetSubOperationError?) -> Void) {
            delegate.keychainQueue.async { [weak self] in
                guard let self = self, let assetKey = self.delegate.key(for: asset.logicalAsset) else {
                    callback(.recoverable)
                    return
                }
                DispatchQueue.global(qos: .utility).async {
                    // 500 KB chunk size for videos
                    if let url = assetKey.decrypt(fileAtURL: fileSource, chunkSize: 500000) {
                        do {
                            try FileManager.default.moveItem(at: url, to: asset.localPath, createIntermediateDirectories: true, overwrite: true)
                            callback(nil)
                        } catch {
                            self.log.error(String(describing: error))
                            assertionFailure()
                            try? FileManager.default.removeItem(at: url)
                            callback(.recoverable)
                        }
                    } else {
                        callback(.recoverable)
                    }
                }
            }
        }

        private func decryptPhoto(asset: MutablePhysicalAsset, fileSource: URL, callback: @escaping (AssetSubOperationError?) -> Void) {
            guard let encryptedData = delegate.load(fileSource) else {
                log.error("\(asset.uuid.string): unable to load file - fileSource: \(String(describing: fileSource))")
                callback(.recoverable)
                return
            }
            delegate.keychainQueue.async { [weak self] in
                guard let self = self, let assetKey = self.delegate.key(for: asset.logicalAsset) else {
                    callback(.recoverable)
                    return
                }

                DispatchQueue.global(qos: .utility).async {
                    // must drain autoreleasepool after each encrypt/decrypt, because Crypto PGP framework uses NSData. Without this, memory usage will accumulate over time (memory leak)
                    autoreleasepool {
                        guard let data = try? assetKey.decrypt(encryptedData) else {
                            self.log.error("\(asset.uuid.string): failed to decrypt data")
                            callback(.recoverable)
                            return
                        }
                        if self.delegate.write(data, to: asset.localPath) {
                            callback(nil)
                        } else {
                            self.log.error("\(asset.uuid.string): failed to write decrypted data to disk")
                            callback(.recoverable)
                        }
                    }
                }
            }
        }
    }
}
