//
//  Schema0-1.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 20/12/2020.
//  Copyright © 2020 Vinoth Ramiah. All rights reserved.
//

import Foundation

extension ServerUpgrader {
    func upgradeFromSchema0(callback: @escaping ClosureBool) {
        guard let userKey = userKey, let api = api, let dataService = dataService else {
            callback(false)
            return
        }
        let dataManager = DataManager(dataService: dataService, simultaneousTransfers: 4)

        let queue = DispatchQueue(label: String(describing: ServerUpgrader.self) + ".upgradeFromSchema0", qos: .userInitiated)
        api.fetchGroups(callbackOn: queue) { [weak api] (success, allGroupData) in
            let log = Logger.self
            guard let api = api, success else {
                log.error("FetchGroups callback failed")
                DispatchQueue.main.async { callback(false) }
                return
            }
            let allGroupData = allGroupData ?? [String: [String: Any]]()
            api.getSchema0Data(callbackOn: queue) { [weak self] (success, data) in
                guard let self = self, success else {
                    log.error("GetAssetsLegacy callback failed")
                    DispatchQueue.main.async { callback(false) }
                    return
                }
                let data = data ?? [[String: Any]]()
                let dispatchGroup = DispatchGroup()
                var failed = false
                var assetKeys = [String: String]()
                var assetMD5s = [String: String]()
                self.progress = (completed: 0, total: data.count)
                do {
                    for asset in data {
                        guard let assetID = asset["id"] as? String else { throw "'id' key missing from server response" }
                        var assetKeyOpt: CryptoPrivateKey?
                        if let tripKeyStringEnc = asset["tripkey"] as? String {
                            // re-encrypt asset key with user key
                            let tripKeyString = try userKey.decrypt(tripKeyStringEnc, signedBy: userKey)
                            let tripKey = try CryptoPrivateKey(key: tripKeyString, password: nil, for: .group)
                            guard let assetKeyStringEnc = asset["assetkey"] as? String else { throw "'assetkey' key missing from server response" }
                            let assetKeyString = try tripKey.decrypt(assetKeyStringEnc, signedBy: tripKey)
                            let newAssetKeyStringEnc = userKey.encrypt(assetKeyString, signed: userKey)
                            assetKeys[assetID] = newAssetKeyStringEnc
                            assetKeyOpt = try CryptoPrivateKey(key: assetKeyString, password: nil, for: .asset)
                        } else {
                            if let assetKeyStringEnc = asset["key"] as? String {
                                // asset key encrypted with user key
                                let assetKeyString = try userKey.decrypt(assetKeyStringEnc, signedBy: userKey)
                                assetKeyOpt = try CryptoPrivateKey(key: assetKeyString, password: nil, for: .asset)
                            } else if let sharedAssetKeyStringEnc = asset["sharedkey"] as? String {
                                // (shared) asset key encrypted with group key and signed by a group member
                                guard let groupID = asset["groupid"] as? String else { throw "'groupid' key missing from server response" }
                                guard let groupData = allGroupData[groupID] else { throw "could not find groupdata for groupid: \(groupID)" }
                                guard let groupKeyStringEnc = groupData["key"] as? String else { throw "group key missing from groupdata" }
                                let groupKeyString = try userKey.decrypt(groupKeyStringEnc, signedBy: userKey)
                                let groupKey = try CryptoPrivateKey(key: groupKeyString, password: nil, for: .group)
                                guard let groupMemberData = groupData["members"] as? [[String: String]] else { throw "group member data missing from groupdata" }
                                let memberPublicKeyStrings: [String] = try groupMemberData.map{ guard let publicKeyString = $0["key"] else { throw "group member public key missing from groupdata" }; return publicKeyString }
                                let memberPublicKeys = try memberPublicKeyStrings.map{ try CryptoPublicKey(key: $0, for: .user) }
                                let (assetKeyString, _) = try groupKey.decrypt(sharedAssetKeyStringEnc, signedByOneOf: memberPublicKeys)
                                assetKeyOpt = try CryptoPrivateKey(key: assetKeyString, password: nil, for: .asset)
                            } else {
                                throw "unexpected – multiple keys missing from server response"
                            }
                        }
                        guard let assetKey = assetKeyOpt else { throw "failed to derive asset key" }
                        if asset["md5"] is NSNull {
                            // download original file, decrypt, calculate md5 hash, encrypt hash with asset key
                            guard let originalURL = URL(optionalString: asset["remotepathorig"] as? String) else { throw "'remotepathorig' key missing from server response, or has invalid data" }
                            let tempURL = Globals.Directories.tmp.appendingPathComponent(ProcessInfo().globallyUniqueString, isDirectory: false)
                            dispatchGroup.enter()
                            dataManager.downloadFile(at: originalURL, to: tempURL, priority: .high) { [weak self] success in
                                var md5Encrypted: String?
                                var thrownError: Error?
                                do {
                                    guard success else { throw "download failed for assetID: \(assetID)" }
                                    let data = try Data(contentsOf: tempURL)
                                    let originalImageData = try assetKey.decrypt(data)
                                    let md5String = originalImageData.md5().base64EncodedString()
                                    md5Encrypted = assetKey.encrypt(md5String, signed: assetKey)
                                } catch {
                                    thrownError = error
                                }
                                try? FileManager.default.removeItem(at: tempURL)
                                queue.async {
                                    if let md5Encrypted = md5Encrypted {
                                        assetMD5s[assetID] = md5Encrypted
                                    } else if let error = thrownError {
                                        log.error(String(describing: error))
                                        failed = true
                                    }
                                    dispatchGroup.leave()
                                    if let self = self {
                                        self.progress = (self.progress.completed + 1, self.progress.total)
                                    }
                                }
                            }
                        } else {
                            self.progress = (self.progress.completed + 1, self.progress.total)
                        }
                    }
                } catch {
                    failed = true
                    log.error(String(describing: error))
                }
                dispatchGroup.notify(queue: queue) { [weak api] in
                    guard let api = api, !failed else { DispatchQueue.main.async { callback(false) }; return }
                    api.patchSchema0Data(assetKeys: assetKeys, assetMD5s: assetMD5s, callbackOn: queue) { success in
                        DispatchQueue.main.async { callback(success) }
                    }
                }
            }
        }
    }
}
