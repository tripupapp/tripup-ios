//
//  MD5FixerOperation.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 08/07/2021.
//  Copyright © 2021 Vinoth Ramiah. All rights reserved.
//

import Foundation
import Photos

class MD5FixerOperation: UpgradeOperation {
    private var modelController: ModelController?
    private var keychainDelegate: KeychainDelegateObject?
    private var assetOperationDelegate: AssetOperationDelegateObject?
    private var operationQueue: OperationQueue?

    override func main() {
        super.main()

        guard let database = database, let dataService = dataService, let api = api, let primaryUser = user, let primaryUserKey = userKey, let keychain = keychain else {
            log.error("missing operation dependency - \(String(describing: self.database)), \(String(describing: self.dataService)), \(String(describing: self.api)), \(String(describing: self.user)), \(String(describing: self.userKey)), \(String(describing: self.keychain))")
            finish(success: false)
            return
        }
        modelController = ModelController(assetDatabase: database, groupDatabase: database, userDatabase: database)

        let allAssets = database.allAssets
        let allMutableAssets: [AssetManager.MutableAsset]
        do {
            allMutableAssets = try database.mutableAssets(forAssetIDs: allAssets.keys)
        } catch {
            log.error("no mutable assets - error: \(String(describing: error))")
            finish(success: false)
            return
        }

        self.progress = (completed: 0, total: allMutableAssets.count)
        var mutableAssetsToReImport = [UUID: AssetManager.MutableAsset]()
        for mutableAsset in allMutableAssets {
            guard mutableAsset.ownerID == primaryUser.uuid else {
                // don't upgrade other peoples assets
                self.progress = (self.progress.completed + 1, self.progress.total)
                continue
            }
            mutableAsset.database = modelController

            guard mutableAsset.md5 != nil else {
                // missing md5 indicates this asset has yet to be imported or to complete fetched state, so skip
                self.progress = (self.progress.completed + 1, self.progress.total)
                continue
            }

            guard let localIdentifier = mutableAsset.localIdentifier else {
                self.progress = (self.progress.completed + 1, self.progress.total)
                continue
            }

            let fetchOptions = PHFetchOptions()
            // only allow photos and videos; filter out audio and other types for now
            fetchOptions.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
                NSPredicate(format: "%K == %d", #keyPath(PHAsset.mediaType), PHAssetMediaType.image.rawValue),
                NSPredicate(format: "%K == %d", #keyPath(PHAsset.mediaType), PHAssetMediaType.video.rawValue)
            ])
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: #keyPath(PHAsset.creationDate), ascending: true)]

            guard let phAsset = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: fetchOptions).firstObject else {
                self.progress = (self.progress.completed + 1, self.progress.total)
                mutableAsset.localIdentifier = nil
                continue
            }
            let phAssetResources = PHAssetResource.assetResources(for: phAsset)
            guard let assetResource = phAssetResources.first(where: { $0.type == (mutableAsset.type == .photo ? .photo : .video) }) else {
                self.progress = (self.progress.completed + 1, self.progress.total)
                mutableAsset.localIdentifier = nil
                continue
            }

            // obtain md5 of resource
            let dispatchGroup = DispatchGroup()
            let md5Summer = MD5Summer()
            let requestOptions = PHAssetResourceRequestOptions()
            requestOptions.isNetworkAccessAllowed = true
            dispatchGroup.enter()
            PHAssetResourceManager.default().requestData(for: assetResource, options: requestOptions, dataReceivedHandler: md5Summer.input) { error in
                if let error = error {
                    md5Summer.abort(error)
                } else {
                    md5Summer.finalise()
                }
                dispatchGroup.leave()
            }
            dispatchGroup.wait()
            guard case .success(let md5) = md5Summer.result else {
                finish(success: false)
                return
            }

            guard mutableAsset.md5 != md5 else {
                // exact data already saved. skipping...
                self.progress = (self.progress.completed + 1, self.progress.total)
                continue
            }

            // remove existing files – needed for stopping the bypass of fetching state
            try? FileManager.default.removeItem(at: mutableAsset.physicalAssets.low.localPath, idempotent: true)
            try? FileManager.default.removeItem(at: mutableAsset.physicalAssets.original.localPath, idempotent: true)

            // remove remote paths - needed for stopping the bypass of encrypting + uploading states
            mutableAsset.physicalAssets.low.remotePath = nil
            mutableAsset.physicalAssets.original.remotePath = nil

            mutableAssetsToReImport[mutableAsset.uuid] = mutableAsset
        }

        guard mutableAssetsToReImport.isNotEmpty else {
            finish(success: true)
            return
        }
        keychainDelegate = KeychainDelegateObject(keychain: keychain, primaryUserKey: primaryUserKey)
        assetOperationDelegate = AssetOperationDelegateObject(assetController: modelController!, dataService: dataService, webAPI: api, photoLibrary: PhotoLibrary(), keychainQueue: .global())
        assetOperationDelegate?.keychainDelegate = keychainDelegate

        operationQueue = OperationQueue()
        queueImportOperation(for: Array(mutableAssetsToReImport.values))
    }

    private func queueImportOperation(for mutableAssets: [AssetManager.MutableAsset]) {
        guard let assetOperationDelegate = assetOperationDelegate else {
            return
        }
        let assets: [AssetManager.MutableAsset] = mutableAssets.suffix(5)
        let operation = AssetManager.AssetImportOperation(assets: assets, delegate: assetOperationDelegate, currentState: AssetManager.AssetImportOperation.KeyGenerated.self)
        operation.completionBlock = {
            if operation.currentState is AssetManager.AssetImportOperation.Success {
                self.progress = (self.progress.completed + assets.count, self.progress.total)
                let remainingAssets: [AssetManager.MutableAsset] = mutableAssets.dropLast(5)
                if remainingAssets.isNotEmpty {
                    self.queueImportOperation(for: remainingAssets)
                } else {
                    self.finish(success: true)
                }
            } else {
                self.finish(success: false)
            }
        }
        operationQueue?.addOperation(operation)
    }
}


