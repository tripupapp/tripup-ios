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

    override func main() {
        super.main()

        guard let database = database, let api = api, let primaryUser = user, let keychain = keychain else {
            log.error("missing operation dependency - \(String(describing: self.database)), \(String(describing: self.api)), \(String(describing: self.user)), \(String(describing: self.keychain))")
            finish(success: false)
            return
        }
        modelController = ModelController(assetDatabase: database, groupDatabase: database, userDatabase: database)

        modelController?.allAssets { [weak self] (allAssets) in
            let allAssets = allAssets.filter{ $0.value.imported && $0.value.ownerID == primaryUser.uuid }
            guard allAssets.isNotEmpty else {
                self?.progress = (completed: 1, total: 1)
                self?.finish(success: true)
                return
            }

            self?.modelController?.localIdentifiers(forAssets: allAssets.values) { [weak self] (assets2localids) in
                let photoLibrary = PhotoLibrary()
                photoLibrary.fetchAssets(withLocalIdentifiers: assets2localids.values) { (localids2phasset) in
                    self?.modelController?.mutableAssets(for: allAssets.keys) { [weak self] (result) in
                        guard let self = self else {
                            return
                        }
                        switch result {
                        case .success(let (mutableAssets, _)) where mutableAssets.isNotEmpty:
                            self.progress = (completed: 0, total: mutableAssets.count * 2)

                            var assetids2filename = [String: String]()
                            var assetids2encryptedfilenames = [String: String]()
                            for mutableAsset in mutableAssets {
                                let assetID = mutableAsset.uuid
                                mutableAsset.database = self.modelController
                                guard let asset = allAssets[assetID], let localID = assets2localids[asset], let phasset = localids2phasset[localID] else {
                                    self.progress = (self.progress.completed + 1, self.progress.total)
                                    continue
                                }
                                guard let filename = photoLibrary.resource(forPHAsset: phasset, type: asset.type)?.originalFilename else {
                                    self.progress = (self.progress.completed + 1, self.progress.total)
                                    continue
                                }
                                guard let fingerprint = mutableAsset.fingerprint else {
                                    self.log.error("missing fingerprint - assetID: \(assetID.string)")
                                    self.finish(success: false)
                                    return
                                }
                                guard let assetKey = try? keychain.retrievePrivateKey(withFingerprint: fingerprint, keyType: .asset) else {
                                    self.log.error("missing asset key - assetID: \(assetID.string)")
                                    self.finish(success: false)
                                    return
                                }
                                autoreleasepool {
                                    let encryptedFilename = assetKey.encrypt(filename, signed: assetKey)
                                    assetids2encryptedfilenames[assetID.string] = encryptedFilename
                                }
                                assetids2filename[assetID.string] = filename
                                self.progress = (self.progress.completed + 1, self.progress.total)
                            }

                            api.updateFilenames(assetids2encryptedfilenames, callbackOn: .global()) { [weak self] (success) in
                                guard let self = self else {
                                    return
                                }
                                self.progress = (Int(Double(self.progress.total) * 0.9), self.progress.total)
                                if success {
                                    for mutableAsset in mutableAssets {
                                        if let filename = assetids2filename[mutableAsset.uuid.string] {
                                            self.modelController?.save(filename: filename, for: mutableAsset)
                                        }
                                    }
                                    self.finish(success: true)
                                } else {
                                    self.log.error("error with api call")
                                    self.finish(success: false)
                                }
                            }
                        case .success(_):
                            self.progress = (completed: 3, total: 3)
                            self.finish(success: true)
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
