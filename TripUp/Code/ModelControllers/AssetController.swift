//
//  AssetController.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 27/09/2019.
//  Copyright © 2019 Vinoth Ramiah. All rights reserved.
//

import Foundation
import Photos.PHAsset

protocol AssetFinder {
    func allAssets(callback: @escaping ([UUID: Asset]) -> Void)
}

protocol AssetController: AnyObject, AssetFinder {
    func localIdentifier(forAsset asset: Asset, callback: @escaping (String?) -> Void)
    func assetIDlocalIDMap(callback: @escaping ([UUID: String]) -> Void)
    func remove<T>(assets: T) where T: Collection, T.Element == Asset
    func remove<T>(assets: T) where T: Collection, T.Element == AssetManager.MutableAsset
    func mutableAssets<T>(for assetIDs: T, callback: @escaping (Result<([AssetManager.MutableAsset], [UUID]), Error>) -> Void) where T: Collection, T.Element == UUID
    func unlinkedAsset(withMD5Hash md5: Data, callback: @escaping (Asset?) -> Void)
    func unlinkedAssets(callback: @escaping ([UUID: Asset]?) -> Void)
    func `switch`(localIdentifier: String, fromAssetID oldAssetID: UUID, toAssetID newAssetID: UUID)
    func deletedAssetIDs(callback: @escaping ([UUID]?) -> Void)
}

protocol AssetAPI {
    func getAssets(callbackOn queue: DispatchQueue, resultHandler: @escaping (Bool, [[String: Any]]?) -> Void)
}

extension ModelController {
    func cloudStorageUsed(callback: @escaping (UsedStorage?) -> Void) {
        databaseQueue.async { [weak self] in
            let cloudStorageUsed = self?.assetDatabase.cloudStorageUsed
            DispatchQueue.global().async {
                callback(cloudStorageUsed)
            }
        }
    }
}

extension ModelController {
    func consolidateWithIOSPhotoLibrary(orderedPHAssets: [PHAsset], localIDsforPHAssets: [String], callback: @escaping Closure) {
        databaseQueue.async(flags: .barrier) { [weak self] in
            defer {
                DispatchQueue.main.async {
                    callback()
                }
            }
            guard let self = self else {
                return
            }
            let allAssets = self.allAssets
            let assetIDsToLocalIDs = self.assetIDlocalIDMap

            let localIDsforPHAssets = Set(localIDsforPHAssets)
            var previouslyAddedIOSAssetIDs = Set<String>()
            var assetsWithInvalidLocalIDs = [Asset]()
            var invalidAssetIDs = [UUID]()

            for (assetID, asset) in allAssets {
                if let localID = assetIDsToLocalIDs[assetID] {
                    if localIDsforPHAssets.contains(localID) {
                        previouslyAddedIOSAssetIDs.insert(localID)
                    } else {
                        if asset.imported {
                            assetsWithInvalidLocalIDs.append(asset)
                        } else {
                            invalidAssetIDs.append(assetID)
                        }
                    }
                } else if !asset.imported {
                    invalidAssetIDs.append(assetID)
                }
            }
            let newPHAssets = orderedPHAssets.filter{ phasset in !previouslyAddedIOSAssetIDs.contains(phasset.localIdentifier) }

            // import new phassets into TripUp
            if newPHAssets.isNotEmpty {
                let assets: [(Asset, String)] = newPHAssets.map { asset in
                    return (Asset(
                        uuid: UUID(),   // FIXME: check uuid isn't already taken
                        type: AssetType(iosMediaType: asset.mediaType),
                        ownerID: self.primaryUserID,
                        creationDate: asset.creationDate,
                        location: TULocation(asset.location),
                        duration: asset.duration == 0 ? nil : asset.duration,
                        pixelSize: CGSize(width: asset.pixelWidth, height: asset.pixelHeight),
                        imported: false
                    ), asset.localIdentifier)
                }
                do {
                    try self.addFromDevice(assets)
                } catch {
                    self.log.error(String(describing: error))
                    assertionFailure()
                }
            }

            // prune non-existant localIdentifiers
            if assetsWithInvalidLocalIDs.isNotEmpty {
                self.pruneLocalIDs(for: assetsWithInvalidLocalIDs)
            }

            // remove unimported phassets from TripUp
            if invalidAssetIDs.isNotEmpty {
                self.assetSyncManager?.removeInvalidAssets(ids: invalidAssetIDs)
            }
        }
    }

    func refreshAssets(callback: ClosureBool? = nil) {
        let callbackOnMain = { (continueNetworkOps: Bool) in
            if let callback = callback {
                DispatchQueue.main.async {
                    callback(continueNetworkOps)
                }
            }
        }
        guard let assetAPI = assetAPI else {
            log.warning("assetAPI not set")
            callbackOnMain(false)
            return
        }
        assetAPI.getAssets(callbackOn: databaseQueue) { [weak self] (success: Bool, result: [[String: Any]]?) in
            guard let self = self, success else {
                callbackOnMain(false)
                return
            }
            let clientAssets = self.allAssets
            let result = result ?? [[String: Any]]()    // empty (and nil) result is valid – signifies that all assets should be deleted (unimported assets are dealt with below in the delete section)
            let data: [UUID: [String: Any]] = Dictionary(grouping: result, by: { UUID(uuidString: $0["uuid"] as! String)! }).mapValues{ $0[0] }

            let serverAssetIDs = Set(data.keys)
            let clientAssetIDs = Set(clientAssets.keys)
            let newAssetIDs = serverAssetIDs.subtracting(clientAssetIDs)
            let deletedAssetIDs = clientAssetIDs.subtracting(serverAssetIDs)

            if newAssetIDs.isNotEmpty {
                let groups = self.allGroups
                var decryptedData = [UUID: [String: Any?]]()
                for id in newAssetIDs {
                    guard let assetData = data[id] else {
                        self.log.error("missing server data - assetid: \(id)")
                        assertionFailure()
                        continue
                    }
                    guard let keyData = assetData["key"] as? String, keyData.isNotEmpty else {
                        self.log.error("missing key data - assetid: \(id))")
                        assertionFailure()
                        continue
                    }
                    guard let ownerIDstring = assetData["ownerid"] as? String, let ownerID = UUID(uuidString: ownerIDstring) else {
                        self.log.error("missing ownerid - assetid: \(id))")
                        assertionFailure()
                        continue
                    }
                    var decryptionKeyPair: (CryptoPrivateKey, [CryptoPublicKey])!
                    if ownerID == self.primaryUserID {
                        decryptionKeyPair = (self.primaryUserKey, [self.primaryUserKey])
                    } else {
                        guard let groupIDstring = assetData["groupid"] as? String else {
                            self.log.error("missing groupid - assetid: \(String(describing: id))")
                            assertionFailure()
                            continue
                        }
                        guard let groupID = UUID(uuidString: groupIDstring), let group = groups[groupID] else {
                            self.log.error("missing group - assetid: \(id)), groupid: \(groupIDstring)")
                            assertionFailure()
                            continue
                        }
                        var groupKey: CryptoPrivateKey!
                        do {
                            groupKey = try self.keychain.retrievePrivateKey(withFingerprint: group.fingerprint, keyType: .group)
                        } catch {
                            self.log.error("error retrieving group private key - assetid: \(id), group: \(group), error: \(String(describing: error))")
                            assertionFailure()
                            continue
                        }
                        var userKeys = [CryptoPublicKey]()
                        for user in group.members {
                            do {
                                if let userKey = try self.keychain.retrievePublicKey(withFingerprint: user.fingerprint, keyType: .user) {
                                    userKeys.append(userKey)
                                } else {
                                    throw "user key not found"
                                }
                            } catch {
                                self.log.error("assetid: \(id), user: \(user), error: \(String(describing: error))")
                                assertionFailure()
                                continue
                            }
                        }
                        decryptionKeyPair = (groupKey, userKeys)
                    }
                    var assetKey: CryptoPrivateKey!
                    var md5: Data!
                    var creationDate: Date?
                    var location: TULocation?
                    var duration: TimeInterval?
                    autoreleasepool {
                        do {
                            let keyString = try decryptionKeyPair.0.decrypt(keyData, signedByOneOf: decryptionKeyPair.1).0
                            do {
                                assetKey = try self.keychain.createPrivateKey(for: .asset, from: keyString, password: nil, saveToKeychain: true)
                            } catch KeychainError.duplicate(_) {
                                assetKey = try self.keychain.createPrivateKey(for: .asset, from: keyString, password: nil, saveToKeychain: false)
                            }
                            guard let md5String = assetData["md5"] as? String else {
                                throw "md5 string not found"
                            }
                            let md5StringDecrypted = try assetKey.decrypt(md5String, signedBy: assetKey)
                            guard let md51 = Data(base64Encoded: md5StringDecrypted) else {
                                throw "invalid md5 string - md5String: \(md5StringDecrypted)"
                            }
                            md5 = md51
                            if let dateString = assetData["createdate"] as? String {
                                let dateStringDecrypted = try assetKey.decrypt(dateString, signedBy: assetKey)
                                if let date = Date(iso8601: dateStringDecrypted) {
                                    creationDate = date
                                } else {
                                    self.log.error("invalid date string - assetID: \(id), dateString: \(dateStringDecrypted)")
                                    assertionFailure()
                                }
                            }
                            if let locationString = assetData["location"] as? String {
                                let locationStringDecrypted = try assetKey.decrypt(locationString, signedBy: assetKey)
                                if let tuLocation = TULocation(locationStringDecrypted) {
                                    location = tuLocation
                                } else {
                                    self.log.error("invalid location string - assetID: \(id), locationString: \(locationStringDecrypted)")
                                    assertionFailure()
                                }
                            }
                            if let durationString = assetData["duration"] as? String {
                                let durationStringDecrypted = try assetKey.decrypt(durationString, signedBy: assetKey)
                                if let durationInterval = TimeInterval(durationStringDecrypted) {
                                    duration = durationInterval
                                } else {
                                    self.log.error("invalid duration string - assetID: \(id), durationString: \(durationStringDecrypted)")
                                    assertionFailure()
                                }
                            }
                        } catch {
                            self.log.error("assetID: \(id), assetData: \(assetData), error: \(String(describing: error))")
                            assertionFailure()
                        }
                    }
                    guard assetKey != nil && md5 != nil else {
                        continue
                    }
                    decryptedData[id] = [
                        "key": assetKey,
                        "md5": md5,
                        "createdate": creationDate,
                        "location": location,
                        "duration": duration
                    ]
                }
                assert(newAssetIDs.count == decryptedData.count)
                do {
                    try self.addFromServer(decryptedData: decryptedData, fullServerData: data)
                } catch {
                    self.log.error("failed to add data from server - error: \(String(describing: error))")
                    for decryptedValues in decryptedData.values {
                        if let assetKey = decryptedValues["key"] as? CryptoPrivateKey {
                            try? self.keychain.deletePrivateKey(assetKey)
                        }
                    }
                    assertionFailure()
                }
            }

            let mutualAssetIDs = serverAssetIDs.intersection(clientAssetIDs)
            if mutualAssetIDs.isNotEmpty {
                let mutualAssets = clientAssets.filter{ mutualAssetIDs.contains($0.key) }
                assert(mutualAssetIDs.count == mutualAssets.count)
                self.sync(data, withExistingAssets: mutualAssets)
            }

            let removedAssetIDs = deletedAssetIDs.filter {
                let deletedAsset = clientAssets[$0]!
                return deletedAsset.imported && !deletedAsset.hidden
            }
            if removedAssetIDs.isNotEmpty {
                self.assetSyncManager?.removeDeletedAssets(ids: removedAssetIDs)
            }
            callbackOnMain(true)
        }
    }
}

private extension ModelController {
    private var allAssets: [UUID: Asset] {
        return assetDatabase.allAssets
    }

    private var assetIDlocalIDMap: [UUID: String] {
        return assetDatabase.assetIDLocalIDMap
    }

    private func addFromDevice<T>(_ assets: T) throws where T: Collection, T.Element == (Asset, String) {
        try assetDatabase.addLocalAssets(assets)
        observers(notify: .new(Set(assets.map{ $0.0 })))
    }

    private func addFromServer(decryptedData: [UUID: [String: Any?]], fullServerData: [UUID: [String: Any]]) throws {
        let assets = try assetDatabase.addRemoteAssets(from: decryptedData, serverData: fullServerData)
        observers(notify: .new(Set(assets)))
    }

    private func pruneLocalIDs(for assets: [Asset]) {
        do {
            try assetDatabase.pruneLocalIDs(forAssetIDs: assets.map{ $0.uuid })
        } catch {
            log.error(String(describing: error))
            assertionFailure()
        }
    }

    private func sync(_ data: [UUID: [String: Any]], withExistingAssets existingAssets: [UUID: Asset]) {
        do {
            let (updatedAssets, groupsUpdate) = try assetDatabase.sync(data, withAssetIDs: existingAssets.keys)
            if let groupsUpdate = groupsUpdate {
                for groupUpdates in groupsUpdate {
                    observers(notify: .updated(groupUpdates.0, to: groupUpdates.1))
                }
            }
            if let updatedAssets = updatedAssets {
                for updatedAsset in updatedAssets {
                    guard let oldAsset = existingAssets[updatedAsset.uuid] else { assertionFailure(); continue }
                    observers(notify: .updated(oldAsset, updatedAsset))
                }
            }
        } catch {
            log.error(String(describing: error))
            assertionFailure()
        }
    }
}

extension ModelController: AssetFinder {
    func allAssets(callback: @escaping ([UUID: Asset]) -> Void) {
        databaseQueue.async { [weak self] in
            let allAssets = self?.allAssets
            DispatchQueue.global().async {
                callback(allAssets ?? [UUID: Asset]())
            }
        }
    }
}

extension ModelController: AssetController {
    func localIdentifier(forAsset asset: Asset, callback: @escaping (String?) -> Void) {
        databaseQueue.async { [weak self] in
            var localIdentifier: String?
            do {
                localIdentifier = try self?.assetDatabase.localIdentifier(forAssetID: asset.uuid)
            } catch {
                self?.log.error(String(describing: error))
                assertionFailure()
            }
            DispatchQueue.global().async {
                callback(localIdentifier)
            }
        }
    }

    func assetIDlocalIDMap(callback: @escaping ([UUID: String]) -> Void) {
        databaseQueue.async { [weak self] in
            let idMap = self?.assetIDlocalIDMap
            DispatchQueue.global().async {
                callback(idMap ?? [UUID: String]())
            }
        }
    }

    func remove<T>(assets: T) where T: Collection, T.Element == Asset {
        databaseQueue.async(flags: .barrier) { [weak self] in
            guard let self = self else {
                return
            }
            do {
                if let groupsChanged = try self.assetDatabase.remove(assetIDs: assets.map{ $0.uuid }) {
                    for groupChanges in groupsChanged {
                        self.observers(notify: .updated(groupChanges.0, to: groupChanges.1))
                    }
                }
                self.observers(notify: .deleted(Set(assets)))
            } catch {
                self.log.error(String(describing: error))
                assertionFailure()
            }
        }
    }

    func remove<T>(assets: T) where T: Collection, T.Element == AssetManager.MutableAsset {
        remove(assets: assets.map{ Asset($0) })
    }

    func mutableAssets<T>(for assetIDs: T, callback: @escaping (Result<([AssetManager.MutableAsset], [UUID]), Error>) -> Void) where T: Collection, T.Element == UUID {
        databaseQueue.async { [weak self] in
            do {
                guard let self = self else {
                    throw "self deallocated"
                }
                let assets: [AssetManager.MutableAsset] = try self.assetDatabase.mutableAssets(forAssetIDs: assetIDs)
                let foundIDs = assets.map{ $0.uuid }
                let missingIDs = Set(assetIDs).subtracting(foundIDs)
                DispatchQueue.global().async {
                    callback(.success((assets, Array(missingIDs))))
                }
            } catch {
                DispatchQueue.global().async {
                    callback(.failure(error))
                }
            }
        }
    }

    func unlinkedAsset(withMD5Hash md5: Data, callback: @escaping (Asset?) -> Void) {
        databaseQueue.async { [weak self] in
            let asset = self?.assetDatabase.unlinkedAsset(withMD5Hash: md5)
            DispatchQueue.global().async {
                callback(asset)
            }
        }
    }

    func unlinkedAssets(callback: @escaping ([UUID: Asset]?) -> Void) {
        databaseQueue.async { [weak self] in
            let assets = self?.assetDatabase.unlinkedAssets()
            DispatchQueue.global().async {
                callback(assets)
            }
        }
    }

    func `switch`(localIdentifier: String, fromAssetID oldAssetID: UUID, toAssetID newAssetID: UUID) {
        databaseQueue.async(flags: .barrier) { [weak self] in
            do {
                try self?.assetDatabase.switch(localIdentifier: localIdentifier, fromAssetID: oldAssetID, toAssetID: newAssetID)
            } catch {
                self?.log.error(String(describing: error))
                assertionFailure()
            }
        }
    }

    func deletedAssetIDs(callback: @escaping ([UUID]?) -> Void) {
        databaseQueue.async { [weak self] in
            let deletedAssetIDs = self?.assetDatabase.deletedAssetIDs
            DispatchQueue.global().async {
                callback(deletedAssetIDs)
            }
        }
    }
}

extension ModelController: MutableAssetDatabase {
    func fingerprint(for asset: AssetManager.MutableAsset) -> String? {
        databaseQueue.sync {
            var fingerprint: String?
            do {
                fingerprint = try assetDatabase.fingerprint(forAssetID: asset.uuid)
            } catch {
                log.error(String(describing: error))
                assertionFailure()
            }
            return fingerprint
        }
    }

    func save(fingerprint: String, for asset: AssetManager.MutableAsset) {
        databaseQueue.sync(flags: .barrier) {
            do {
                try assetDatabase.save(fingerprint: fingerprint, forAssetID: asset.uuid)
            } catch {
                log.error(String(describing: error))
                assertionFailure()
            }
        }
    }

    func uti(for asset: AssetManager.MutableAsset) -> String? {
        databaseQueue.sync {
            var uti: String?
            do {
                uti = try assetDatabase.uti(forAssetID: asset.uuid)
            } catch {
                log.error(String(describing: error))
                assertionFailure()
            }
            return uti
        }
    }

    func save(uti: String, for asset: AssetManager.MutableAsset) {
        databaseQueue.sync(flags: .barrier) {
            do {
                try assetDatabase.save(uti: uti, forAssetID: asset.uuid)
            } catch {
                log.error(String(describing: error))
                assertionFailure()
            }
        }
    }

    func localIdentifier(for asset: AssetManager.MutableAsset) -> String? {
        databaseQueue.sync {
            var localIdentifier: String?
            do {
                localIdentifier = try assetDatabase.localIdentifier(forAssetID: asset.uuid)
            } catch {
                log.error(String(describing: error))
                assertionFailure()
            }
            return localIdentifier
        }
    }

    func save(localIdentifier: String?, for asset: AssetManager.MutableAsset) {
        databaseQueue.sync(flags: .barrier) {
            do {
                try assetDatabase.save(localIdentifier: localIdentifier, forAssetID: asset.uuid)
            } catch {
                log.error(String(describing: error))
                assertionFailure()
            }
        }
    }

    func md5(for asset: AssetManager.MutableAsset) -> Data? {
        databaseQueue.sync {
            var md5: Data?
            do {
                md5 = try assetDatabase.md5(forAssetID: asset.uuid)
            } catch {
                log.error(String(describing: error))
                assertionFailure()
            }
            return md5
        }
    }

    func save(md5: Data, for asset: AssetManager.MutableAsset) {
        databaseQueue.sync(flags: .barrier) {
            do {
                try assetDatabase.save(md5: md5, forAssetID: asset.uuid)
            } catch {
                log.error(String(describing: error))
                assertionFailure()
            }
        }
    }

    func cloudFilesize(for asset: AssetManager.MutableAsset) -> UInt64 {
        databaseQueue.sync {
            var filesize: UInt64 = 0
            do {
                filesize = try assetDatabase.cloudFilesize(forAssetID: asset.uuid)
            } catch {
                log.error(String(describing: error))
                assertionFailure()
            }
            return filesize
        }
    }

    func save(cloudFilesize: UInt64, for asset: AssetManager.MutableAsset) {
        databaseQueue.sync(flags: .barrier) {
            do {
                try assetDatabase.save(cloudFilesize: cloudFilesize, forAssetID: asset.uuid)
            } catch {
                log.error(String(describing: error))
                assertionFailure()
            }
        }
    }

    func importStatus(for asset: AssetManager.MutableAsset) -> Bool {
        databaseQueue.sync {
            var imported: Bool = false
            do {
                imported = try assetDatabase.importStatus(forAssetID: asset.uuid)
            } catch {
                log.error(String(describing: error))
                assertionFailure()
            }
            return imported
        }
    }

    func save(importStatus: Bool, for asset: AssetManager.MutableAsset) {
        databaseQueue.sync(flags: .barrier) {
            do {
                let (assetUpdate, groupsUpdate) = try assetDatabase.save(importStatus: importStatus, forAssetID: asset.uuid)
                if let groupsUpdate = groupsUpdate {
                    for groupUpdates in groupsUpdate {
                        observers(notify: .updated(groupUpdates.0, to: groupUpdates.1))
                    }
                }
                observers(notify: .updated(assetUpdate.0, assetUpdate.1))
            } catch {
                log.error(String(describing: error))
                assertionFailure()
            }
        }
    }

    func deleteStatus(for asset: AssetManager.MutableAsset) -> Bool {
        databaseQueue.sync {
            var deleted: Bool = true
            do {
                deleted = try assetDatabase.deleteStatus(forAssetID: asset.uuid)
            } catch {
                log.error(String(describing: error))
                assertionFailure()
            }
            return deleted
        }
    }

    func save(deleteStatus: Bool, for asset: AssetManager.MutableAsset) {
        databaseQueue.sync(flags: .barrier) {
            do {
                let (assetUpdate, groupsUpdate) = try assetDatabase.save(deleteStatus: deleteStatus, forAssetID: asset.uuid)
                if let groupsUpdate = groupsUpdate {
                    for groupUpdates in groupsUpdate {
                        observers(notify: .updated(groupUpdates.0, to: groupUpdates.1))
                    }
                }
                observers(notify: .updated(assetUpdate.0, assetUpdate.1))
            } catch {
                log.error(String(describing: error))
                assertionFailure()
            }
        }
    }

    func remotePath(for asset: AssetManager.MutablePhysicalAsset) -> URL? {
        databaseQueue.sync {
            var remotePath: URL?
            do {
                remotePath = try assetDatabase.remotePath(forAssetID: asset.uuid, atQuality: asset.quality)
            } catch {
                log.error(String(describing: error))
                assertionFailure()
            }
            return remotePath
        }
    }

    func save(remotePath: URL?, for asset: AssetManager.MutablePhysicalAsset) {
        databaseQueue.sync(flags: .barrier) {
            do {
                try assetDatabase.save(remotePath: remotePath, forAssetID: asset.uuid, atQuality: asset.quality)
            } catch {
                log.error(String(describing: error))
                assertionFailure()
            }
        }
    }
}
