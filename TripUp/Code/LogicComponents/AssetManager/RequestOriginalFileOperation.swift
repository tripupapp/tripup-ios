//
//  RequestOriginalFileOperation.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 27/08/2021.
//  Copyright © 2021 Vinoth Ramiah. All rights reserved.
//

import Foundation
import struct AVFoundation.AVFileType

class RequestOriginalFileOperation: AsynchronousOperation {
    enum RequestOriginalFileOperationError: Error {
        case tooManyItems(requested: Int, maxItems: Int)
        case requestError(forAsset: Asset)
    }

    weak var assetController: AssetController?
    weak var assetManager: AssetManager?
    weak var photoLibrary: PhotoLibrary?

    let id = UUID()
    let log = Logger.self
    let maxItems = 50
    var assets = [Asset]()
    var error: Error?
    var progressHandler: ((Int) -> Void)?
    var result = [Asset: URL]()

    override func main() {
        super.main()

        assert(assets.isNotEmpty)
        guard assets.count <= maxItems else {
            log.error("too many requests in one go - count: \(assets.count)")
            error = RequestOriginalFileOperationError.tooManyItems(requested: assets.count, maxItems: maxItems)
            finish()
            return
        }

        let dispatchGroup = DispatchGroup()

        let importedAssets = assets.filter{ $0.imported }
        if importedAssets.isNotEmpty {
            importedAssets.forEach{ _ in dispatchGroup.enter() }
            assetManager?.load(assets: importedAssets, atQuality: .original) { (asset, url, _) in
                DispatchQueue.main.async {
                    if let url = url {
                        self.result[asset] = url
                        self.progressHandler?(1)
                    } else {
                        self.error = self.error ?? RequestOriginalFileOperationError.requestError(forAsset: asset)
                    }
                    dispatchGroup.leave()
                }
            }
        }

        let unimportedAssets = Set(assets).subtracting(importedAssets)
        if unimportedAssets.isNotEmpty {
            unimportedAssets.forEach{ _ in dispatchGroup.enter() }
            assetController?.localIdentifiers(forAssets: unimportedAssets) { [weak self] (localIDMap) in
                self?.photoLibrary?.fetchAssets(withLocalIdentifiers: localIDMap.values) { [weak self] (phAssetMap) in
                    var batchFailed = false
                    for (asset, localIdentifier) in localIDMap {
                        guard !batchFailed else {
                            dispatchGroup.leave()
                            continue
                        }
                        guard let phAsset = phAssetMap[localIdentifier] else {
                            batchFailed = true
                            DispatchQueue.main.async {
                                self?.error = self?.error ?? RequestOriginalFileOperationError.requestError(forAsset: asset)
                                dispatchGroup.leave()
                            }
                            continue
                        }
                        guard let phAssetResource = self?.photoLibrary?.resource(forPHAsset: phAsset, type: asset.type) else {
                            batchFailed = true
                            DispatchQueue.main.async {
                                self?.error = self?.error ?? RequestOriginalFileOperationError.requestError(forAsset: asset)
                                dispatchGroup.leave()
                            }
                            continue
                        }
                        let fileExtension = AVFileType(phAssetResource.uniformTypeIdentifier).fileExtension ?? ""
                        guard let url = FileManager.default.uniqueTempFile(filename: asset.uuid.string, fileExtension: fileExtension) else {
                            batchFailed = true
                            DispatchQueue.main.async {
                                self?.error = self?.error ?? RequestOriginalFileOperationError.requestError(forAsset: asset)
                                dispatchGroup.leave()
                            }
                            continue
                        }
                        guard self?.isCancelled == .some(false) else {
                            batchFailed = true
                            dispatchGroup.leave()
                            continue
                        }
                        self?.photoLibrary?.write(resource: phAssetResource, toURL: url, callback: { (success) in
                            DispatchQueue.main.async {
                                if success {
                                    self?.result[asset] = url
                                    self?.progressHandler?(1)
                                } else {
                                    self?.error = self?.error ?? RequestOriginalFileOperationError.requestError(forAsset: asset)
                                }
                                dispatchGroup.leave()
                            }
                        })
                    }
                }
            }
        }

        dispatchGroup.notify(queue: .main) {
            self.finish()
        }
    }
}
