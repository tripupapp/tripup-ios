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
            finish(success: false)
            return
        }
        modelController = ModelController(assetDatabase: database, groupDatabase: database, userDatabase: database)

        let allAssetsDict = database.allAssets
        guard let allMutableAssets: [AssetManager.MutableAsset] = try? database.mutableAssets(forAssetIDs: allAssetsDict.keys) else {
            finish(success: false)
            return
        }
        let assetsWithIdentifiers = allMutableAssets.sorted(by: { $0.imported && !$1.imported })

        var toKeep = Set<AssetManager.MutableAsset>()
        var duplicates = [AssetManager.MutableAsset]()
        for mutableAsset in assetsWithIdentifiers {
            guard mutableAsset.ownerID == primaryUser.uuid, let localIdentifier = mutableAsset.localIdentifier else {
                continue
            }
            if !toKeep.contains(where: { $0.localIdentifier == localIdentifier }) {
                toKeep.insert(mutableAsset)
            } else {
                duplicates.append(mutableAsset)
            }
        }

        keychainDelegate = KeychainDelegateObject(keychain: keychain, primaryUserKey: primaryUserKey)
        assetOperationDelegate = AssetOperationDelegateObject(assetController: modelController!, dataService: dataService, webAPI: api, photoLibrary: PhotoLibrary(), keychainQueue: .global())
        assetOperationDelegate?.keychainDelegate = keychainDelegate

        let deleteOperation = AssetManager.AssetDeleteOperation(assets: duplicates, delegate: assetOperationDelegate!)
        deleteOperation.completionBlock = {
            if deleteOperation.currentState.value == .deletedFromDisk {
                let fingerprints = duplicates.compactMap{ $0.fingerprint }
                for fingerprint in fingerprints {
                    if let key = self.keychainDelegate!.assetKey(forFingerprint: fingerprint) {
                        try? self.keychainDelegate!.delete(key: key)
                    }
                }
                self.modelController!.remove(assets: duplicates)
                self.finish(success: true)
            } else {
                self.finish(success: false)
            }
        }
        operationQueue = OperationQueue()
        operationQueue?.addOperation(deleteOperation)
    }
}
