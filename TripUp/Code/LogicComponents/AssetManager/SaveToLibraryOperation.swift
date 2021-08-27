//
//  SaveToLibraryOperation.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 26/08/2021.
//  Copyright © 2021 Vinoth Ramiah. All rights reserved.
//

import Foundation
import struct AVFoundation.AVFileType

class SaveToLibraryOperation: AsynchronousOperation {
    enum SaveToLibraryOperationError: Error {
        case encounteredLoadingError(forAsset: Asset)
        case saveToPhotoLibraryError(forAssets: [Asset])
    }

    weak var assetController: AssetController?
    weak var assetManager: AssetManager?
    weak var photoLibrary: PhotoLibrary?

    let id = UUID()
    var assets = [Asset]()
    var alreadySavedAssets = Set<Asset>()
    var error: Error?
    var progressHandler: ((Int) -> Void)?
    var batchSize = 10

    override func main() {
        super.main()

        assetController?.assetIDlocalIDMap(callback: { [weak self] (localIDMap) in
            guard let self = self else {
                return
            }

            let originalSet = Set(self.assets)
            self.assets.removeAll(where: { localIDMap[$0.uuid] != nil })
            self.alreadySavedAssets = originalSet.subtracting(self.assets)

            if self.assets.isEmpty {
                self.finish()
            } else {
                self.assets.sort(by: .creationDate(ascending: true))
                self.saveNextBatch()
            }
        })
    }

    private func saveNextBatch() {
        guard assets.isNotEmpty, !isCancelled, let assetManager = assetManager else {
            finish()
            return
        }

        let batch = assets.suffix(batchSize)
        var loadedAssets = [Asset: (url: URL, uti: AVFileType?)]()
        var failedAsset: Asset?
        let dispatchGroup = DispatchGroup()

        batch.forEach{ _ in dispatchGroup.enter() }
        assetManager.load(assets: batch, atQuality: .original) { [weak assetManager] (asset, url, uti) in
            precondition(.on(assetManager?.assetManagerQueue))
            if let url = url {
                loadedAssets[asset] = (url: url, uti: uti)
            } else {
                failedAsset = asset
            }
            dispatchGroup.leave()
        }

        dispatchGroup.notify(queue: .global()) {
            if let failedAsset = failedAsset {
                self.error = SaveToLibraryOperationError.encounteredLoadingError(forAsset: failedAsset)
                self.finish()
                return
            }
            guard !self.isCancelled else {
                self.finish()
                return
            }
            self.photoLibrary?.save(data: loadedAssets) { [weak self] (result) in
                switch result {
                case .success(let idMap):
                    self?.assetController?.saveLocalIdentifiers(assets2LocalIDs: idMap) { [weak self] (success) in
                        if success {
                            self?.assets.removeLast(batch.count)
                            DispatchQueue.main.async {
                                self?.progressHandler?(batch.count)
                            }
                            self?.saveNextBatch()
                        } else {
                            Logger.self.error("failed to save local identifiers for assets with IDs: \(idMap.keys.map{ $0.uuid })")
                            self?.error = SaveToLibraryOperationError.saveToPhotoLibraryError(forAssets: Array(idMap.keys))
                            self?.finish()
                        }
                    }
                case .failure(let error):
                    self?.error = error
                    self?.finish()
                }
            }
        }
    }
}
