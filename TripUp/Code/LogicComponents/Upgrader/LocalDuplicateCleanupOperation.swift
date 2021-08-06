//
//  LocalDuplicateCleanupOperation.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 05/08/2021.
//  Copyright © 2021 Vinoth Ramiah. All rights reserved.
//

import Foundation

class LocalDuplicateCleanupOperation: UpgradeOperation {
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

        let allAssetsDict = database.allAssets
        let allAssetsSorted = allAssetsDict.values.sorted(by: { $0.imported && !$1.imported })
        let assetID2LocalIDMap = database.assetIDLocalIDMap

        var matchedLocalIDs = Set<String>()
        var duplicateAssetIDs = [UUID]()
        self.progress = (completed: 0, total: allAssetsSorted.count)
        for asset in allAssetsSorted {
            guard let localIdentifier = assetID2LocalIDMap[asset.uuid] else {
                self.progress = (self.progress.completed + 1, self.progress.total)
                continue
            }
            if asset.ownerID != primaryUser.uuid || !matchedLocalIDs.contains(localIdentifier) {
                matchedLocalIDs.insert(localIdentifier)
                self.progress = (self.progress.completed + 1, self.progress.total)
            } else {
                duplicateAssetIDs.append(asset.uuid)
            }
        }

        guard duplicateAssetIDs.isNotEmpty else {
            finish(success: true)
            return
        }

        let duplicateMutableAssets: [AssetManager.MutableAsset]
        do {
            duplicateMutableAssets = try database.mutableAssets(forAssetIDs: duplicateAssetIDs)
        } catch {
            log.error("no mutable assets - error: \(String(describing: error))")
            finish(success: false)
            return
        }
        duplicateMutableAssets.forEach{ $0.database = modelController }

        keychainDelegate = KeychainDelegateObject(keychain: keychain, primaryUserKey: primaryUserKey)
        assetOperationDelegate = AssetOperationDelegateObject(assetController: modelController!, dataService: dataService, webAPI: api, photoLibrary: PhotoLibrary(), keychainQueue: .global())
        assetOperationDelegate?.keychainDelegate = keychainDelegate

        let deleteOperation = AssetManager.AssetDeleteOperation(assets: duplicateMutableAssets, delegate: assetOperationDelegate!)
        deleteOperation.completionBlock = {
            if deleteOperation.currentState.value == .deletedFromDisk {
                let fingerprints = duplicateMutableAssets.compactMap{ $0.fingerprint }
                for fingerprint in fingerprints {
                    if let key = self.keychainDelegate!.assetKey(forFingerprint: fingerprint) {
                        try? self.keychainDelegate!.delete(key: key)
                    }
                }
                self.modelController!.remove(assets: duplicateMutableAssets)
                self.progress = (self.progress.completed + duplicateMutableAssets.count, self.progress.total)
                self.finish(success: true)
            } else {
                self.log.error("unexpected state - \(String(describing: deleteOperation.currentState.value))")
                self.finish(success: false)
            }
        }
        operationQueue = OperationQueue()
        operationQueue?.addOperation(deleteOperation)
    }
}
