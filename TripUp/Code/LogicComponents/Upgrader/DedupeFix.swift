//
//  DedupeFix.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 08/07/2021.
//  Copyright © 2021 Vinoth Ramiah. All rights reserved.
//

import Foundation
import Photos

extension ServerUpgrader {
    private class MD5FixerDependencies {
        var modelController: ModelController?
        var keychainDelegate: KeychainDelegateObject?
        var operationQueue: OperationQueue?
    }

    func fixMD5s(callback: @escaping ClosureBool) {
        guard let database = database, let dataService = dataService, let api = api, let primaryUser = user, let primaryUserKey = userKey, let keychain = keychain else {
            callback(false)
            return
        }
        let modelController = ModelController(assetDatabase: database, groupDatabase: database, userDatabase: database)
        let md5FixerDependencies = MD5FixerDependencies()
        object = md5FixerDependencies
        md5FixerDependencies.modelController = modelController

        let allAssets = database.allAssets
        guard let allMutableAssets: [AssetManager.MutableAsset] = try? database.mutableAssets(forAssetIDs: allAssets.keys) else {
            callback(false)
            return
        }
        self.progress = (completed: 0, total: allMutableAssets.count)
        var mutableAssetsToTerminate = [UUID: AssetManager.MutableAsset]()
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

            let fetchOptions = PHFetchOptions()
            // only allow photos and videos; filter out audio and other types for now
            fetchOptions.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
                NSPredicate(format: "%K == %d", #keyPath(PHAsset.mediaType), PHAssetMediaType.image.rawValue),
                NSPredicate(format: "%K == %d", #keyPath(PHAsset.mediaType), PHAssetMediaType.video.rawValue)
            ])
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: #keyPath(PHAsset.creationDate), ascending: true)]

            guard let localIdentifier = mutableAsset.localIdentifier else {
                if shouldDelete(asset: mutableAsset, from: allMutableAssets, assetsAlreadyMarkedForDeletion: mutableAssetsToTerminate) {
                    mutableAssetsToTerminate[mutableAsset.uuid] = mutableAsset
                } else {
                    self.progress = (self.progress.completed + 1, self.progress.total)
                }
                continue
            }

            guard let phAsset = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: fetchOptions).firstObject else {
                if shouldDelete(asset: mutableAsset, from: allMutableAssets, assetsAlreadyMarkedForDeletion: mutableAssetsToTerminate) {
                    mutableAssetsToTerminate[mutableAsset.uuid] = mutableAsset
                } else {
                    self.progress = (self.progress.completed + 1, self.progress.total)
                }
                mutableAsset.localIdentifier = nil
                continue
            }

            let phAssetResources = PHAssetResource.assetResources(for: phAsset)
            guard let assetResource = phAssetResources.first(where: { $0.type == (mutableAsset.type == .photo ? .photo : .video) }) else {
                if shouldDelete(asset: mutableAsset, from: allMutableAssets, assetsAlreadyMarkedForDeletion: mutableAssetsToTerminate) {
                    mutableAssetsToTerminate[mutableAsset.uuid] = mutableAsset
                } else {
                    self.progress = (self.progress.completed + 1, self.progress.total)
                }
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
                callback(false)
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

        var deleteSuccessful = true
        let dispatchGroup = DispatchGroup()
        if mutableAssetsToTerminate.isNotEmpty {
            dispatchGroup.enter()
            api.delete(assetIDs: mutableAssetsToTerminate.keys.map{ $0.string }, callbackOn: .global()) { success in
                defer {
                    dispatchGroup.leave()
                }
                guard success else {
                    deleteSuccessful = false
                    return
                }
                for mutableAsset in mutableAssetsToTerminate.values {
                    try? FileManager.default.removeItem(at: mutableAsset.physicalAssets.low.localPath, idempotent: true)
                    try? FileManager.default.removeItem(at: mutableAsset.physicalAssets.original.localPath, idempotent: true)
                    if let fingerprint = mutableAsset.fingerprint, let key = try? keychain.retrievePrivateKey(withFingerprint: fingerprint, keyType: .asset) {
                        try? keychain.deletePrivateKey(key)
                    }
                }
                modelController.remove(assets: mutableAssetsToTerminate.values)
                self.progress = (self.progress.completed + mutableAssetsToTerminate.count, self.progress.total)
            }
        }

        dispatchGroup.notify(queue: .global()) {
            guard deleteSuccessful else {
                callback(false)
                return
            }
            guard mutableAssetsToReImport.isNotEmpty else {
                callback(true)
                return
            }
            md5FixerDependencies.keychainDelegate = KeychainDelegateObject(keychain: keychain, primaryUserKey: primaryUserKey)
            let assetOperationDelegate = AssetOperationDelegateObject(assetController: modelController, dataService: dataService, webAPI: api, photoLibrary: PhotoLibrary(), keychainQueue: .global())
            assetOperationDelegate.keychainDelegate = md5FixerDependencies.keychainDelegate
            let operation = AssetManager.AssetImportOperation(assets: Array(mutableAssetsToReImport.values), delegate: assetOperationDelegate, currentState: AssetManager.AssetImportOperation.FetchedFromIOS.self)
            operation.completionBlock = {
                if operation.currentState is AssetManager.AssetImportOperation.Success {
                    self.progress = (self.progress.completed + mutableAssetsToReImport.count, self.progress.total)
                    callback(true)
                } else {
                    callback(false)
                }
            }
            md5FixerDependencies.operationQueue = OperationQueue()
            md5FixerDependencies.operationQueue?.addOperation(operation)
        }
    }

    private func shouldDelete(asset mutableAsset: AssetManager.MutableAsset, from allMutableAssets: [AssetManager.MutableAsset], assetsAlreadyMarkedForDeletion: [UUID: AssetManager.MutableAsset]) -> Bool {
        let duplicateSearchPredicate = { (asset: AssetManager.MutableAsset) -> Bool in
            var duplicate: Bool
            duplicate = asset.type == mutableAsset.type
            duplicate = duplicate && asset.creationDate == mutableAsset.creationDate
            duplicate = duplicate && asset.location == mutableAsset.location
            duplicate = duplicate && asset.duration == mutableAsset.duration
            duplicate = duplicate && asset.pixelSize == mutableAsset.pixelSize
            return duplicate
        }
        if let duplicate = allMutableAssets.first(where: duplicateSearchPredicate), assetsAlreadyMarkedForDeletion[duplicate.uuid] == nil {
            if mutableAsset.type == .photo {
                switch (mutableAsset.originalUTI, duplicate.originalUTI) {
                case (_, _):
                    break
                }
                if mutableAsset.originalUTI == AVFileType("public.png") && duplicate.originalUTI == .jpg {

                }
            }
            return true
        }
        return false
    }
}


