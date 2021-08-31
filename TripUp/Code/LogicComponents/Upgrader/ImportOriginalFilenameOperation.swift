//
//  ImportOriginalFilenameOperation.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 31/08/2021.
//  Copyright © 2021 Vinoth Ramiah. All rights reserved.
//

import Foundation

class ImportOriginalFilenameOperation: UpgradeOperation {
    private var modelController: ModelController?
    private var keychainDelegate: KeychainDelegateObject?
    private var assetOperationDelegate: AssetOperationDelegateObject?

    override func main() {
        super.main()

        guard let database = database, let dataService = dataService, let api = api, let primaryUser = user, let primaryUserKey = userKey, let keychain = keychain else {
            log.error("missing operation dependency - \(String(describing: self.database)), \(String(describing: self.dataService)), \(String(describing: self.api)), \(String(describing: self.user)), \(String(describing: self.userKey)), \(String(describing: self.keychain))")
            finish(success: false)
            return
        }
        modelController = ModelController(assetDatabase: database, groupDatabase: database, userDatabase: database)

        modelController?.allAssets { [weak self] (allAssets) in
            let allAssets = allAssets.filter{ $0.value.imported && $0.value.ownerID == primaryUser.uuid }
            self?.progress = (completed: 0, total: allAssets.count * 2)

            self?.modelController?.localIdentifiers(forAssets: allAssets.values) { [weak self] (assets2localIDs) in
                let photoLibrary = PhotoLibrary()
                photoLibrary.fetchAssets(withLocalIdentifiers: assets2localIDs.values) { (localIDs2PHAsset) in
                    let localIDs2originalFilenames: [String: String] = localIDs2PHAsset.compactMapValues{ phAsset in
                        let resource = photoLibrary.resource(forPHAsset: phAsset, type: .init(iosMediaType: phAsset.mediaType))
                        return resource?.originalFilename
                    }
                    let assetIDs2originalFilenames = assets2localIDs.reduce(into: [UUID: String]()) {
                        $0[$1.key.uuid] = localIDs2originalFilenames[$1.value]
                    }
                    self?.modelController?.mutableAssets(for: allAssets.keys) { [weak self] (result) in
                        guard let self = self else {
                            return
                        }
                        switch result {
                        case .success(let (mutableAssets, _)):
                            for mutableAsset in mutableAssets {
                                if let filename = assetIDs2originalFilenames[mutableAsset.uuid] {
                                    mutableAsset.database = self.modelController
                                    self.modelController?.save(filename: filename, for: mutableAsset)
                                }
                                self.progress = (self.progress.completed + 1, self.progress.total)
                            }
                            self.keychainDelegate = KeychainDelegateObject(keychain: keychain, primaryUserKey: primaryUserKey)
                            self.assetOperationDelegate = AssetOperationDelegateObject(assetController: self.modelController!, dataService: dataService, webAPI: api, photoLibrary: photoLibrary, keychainQueue: .global())
                            self.assetOperationDelegate?.keychainDelegate = self.keychainDelegate
                            self.assetOperationDelegate?.createOnServer(assets: mutableAssets) { [weak self] (result) in
                                guard let self = self else {
                                    return
                                }
                                switch result {
                                case .success(_):
                                    self.progress = (self.progress.completed + mutableAssets.count, self.progress.total)
                                    self.finish(success: true)
                                case .failure(let error):
                                    self.log.error("error with server update - \(String(describing: error))")
                                    self.finish(success: false)
                                }
                            }
                        case .failure(let error):
                            self.log.error("error retrieving mutable assets - \(String(describing: error))")
                            self.finish(success: false)
                        }
                    }
                }
            }
        }
    }
}
