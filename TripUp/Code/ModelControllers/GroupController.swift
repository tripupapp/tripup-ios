//
//  GroupController.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 30/09/2019.
//  Copyright © 2019 Vinoth Ramiah. All rights reserved.
//

import Foundation

protocol GroupFinder: class {
    var allGroups: [UUID: Group] { get }
    func group(for id: UUID) -> Group?
}

protocol GroupCreator: class {
    func createGroup(name: String, callback: @escaping (Bool, Group?) -> Void)
}

protocol GroupDestroyer: class {
    func leaveGroup(_ group: Group, callback: @escaping ClosureBool)
}

protocol GroupManager: GroupFinder, GroupCreator, GroupDestroyer {
    func addUsers<T>(_ users: T, to group: Group, callback: @escaping ClosureBool) where T: Collection, T.Element == User
    func addAssets<T>(_ assets: T, to group: Group, share: Bool, callback: @escaping ClosureBool) where T: Collection, T.Element == Asset
    func removeAssets<T>(_ assets: T, from group: Group, callback: @escaping ClosureBool) where T: Collection, T.Element == Asset
    func shareAssets<T>(_ assets: T, withGroup group: Group, callback: @escaping ClosureBool) where T: Collection, T.Element == Asset
    func unshareAssets<T>(_ assets: T, fromGroup group: Group, callback: @escaping ClosureBool) where T: Collection, T.Element == Asset
}

protocol GroupAPI {
    func fetchGroups(callbackOn queue: DispatchQueue, resultHandler: @escaping (Bool, [String: [String: Any]]?) -> Void)
    func joinGroup(id: UUID, groupKeyCipher: String, callbackOn queue: DispatchQueue, resultHandler: @escaping ClosureBool)
    func fetchAlbumsForAllGroups(callbackOn queue: DispatchQueue, resultHandler: @escaping (Bool, [String: [String: [String]]]?) -> Void)
    func createGroup(name: String, keyStringCipher: String, callbackOn queue: DispatchQueue, resultHandler: @escaping (Bool, UUID?) -> Void)
    func leaveGroup(id: UUID, callbackOn queue: DispatchQueue, resultHandler: @escaping ClosureBool)
    func amendGroup(id: UUID, invites: [(id: UUID, groupKeyCipher: String)], callbackOn queue: DispatchQueue, resultHandler: @escaping ClosureBool)
    func amendGroup(id: UUID, add: Bool, assetIDs: [UUID], callbackOn queue: DispatchQueue, callback: @escaping ClosureBool)
    func amendGroup(id: UUID, share: Bool, assetIDs: [UUID], keyStringsForAssets keyStrings: [String]?, callbackOn queue: DispatchQueue, resultHandler: @escaping (_ success: Bool) -> Void)
    func fetchUsersInGroup(id: UUID, callbackOn queue: DispatchQueue, resultHandler: @escaping (Bool, [String: String]?) -> Void)
}

protocol GroupControllerDelegate: class {
    func setup(_ group: Group)
    func tearDown(_ group: Group)
    func inviteSent<T>(to users: T) where T: Collection, T.Element == User
    func joined(_ group: Group)
    func left(_ group: Group)
    func assetsChanged(for group: Group)
}

extension ModelController {
    private func add(_ group: Group) throws {
        try groupDatabase.addGroup(group)
        observers(notify: .new(group))
    }

    private func remove(_ group: Group) throws {
        try groupDatabase.removeGroup(group)
        observers(notify: .deleted(group))
    }

    private func update(_ group: Group, assetIDs: [UUID], sharedAssetIDs: [UUID]) throws {
        let newGroup = try groupDatabase.updateGroup(id: group.uuid, assetIDs: assetIDs, sharedAssetIDs: sharedAssetIDs)
        if group != newGroup {
            observers(notify: .updated(group, to: newGroup))
        }
    }

    private func add<T>(_ users: T, to group: Group) throws where T: Collection, T.Element == User {
        let newGroup = try groupDatabase.addUsers(withIDs: users.map{ $0.uuid }, toGroupID: group.uuid)
        if group != newGroup {
            observers(notify: .updated(group, to: newGroup))
        }
    }

    private func remove<T>(_ users: T, from group: Group) throws where T: Collection, T.Element == User {
        let newGroup = try groupDatabase.removeUsers(withIDs: users.map{ $0.uuid }, fromGroupID: group.uuid)
        if group != newGroup {
            observers(notify: .updated(group, to: newGroup))
        }
    }

    private func add<T>(_ assets: T, to group: Group) throws where T: Collection, T.Element == Asset {
        let newGroup = try groupDatabase.addAssets(ids: assets.map{ $0.uuid }, toGroupID: group.uuid)
        if group != newGroup {
            observers(notify: .updated(group, to: newGroup))
        }
    }

    private func remove<T>(_ assets: T, from group: Group) throws where T: Collection, T.Element == Asset {
        let newGroup = try groupDatabase.removeAssets(ids: assets.map{ $0.uuid }, fromGroupID: group.uuid)
        if group != newGroup {
            observers(notify: .updated(group, to: newGroup))
        }
    }

    private func share<T>(_ assets: T, with group: Group) throws where T: Collection, T.Element == Asset {
        let newGroup = try groupDatabase.shareAssets(ids: assets.map{ $0.uuid }, withGroupID: group.uuid)
        if group != newGroup {
            observers(notify: .updated(group, to: newGroup))
        }
    }

    private func unshare<T>(_ assets: T, from group: Group) throws where T: Collection, T.Element == Asset {
        let newGroup = try groupDatabase.unshareAssets(ids: assets.map{ $0.uuid }, fromGroupID: group.uuid)
        if group != newGroup {
            observers(notify: .updated(group, to: newGroup))
        }
    }
}

extension ModelController {
    func refreshGroups(callback: ClosureBool? = nil) {
        let callbackOnMain = { (continueNetworkOps: Bool) in
            if let callback = callback {
                DispatchQueue.main.async {
                    callback(continueNetworkOps)
                }
            }
        }
        guard let groupAPI = groupAPI else {
            log.warning("groupAPI missing")
            callbackOnMain(false)
            return
        }
        groupAPI.fetchGroups(callbackOn: databaseQueue) { [weak self] (success, serverData) in
            guard let self = self, success else {
                callbackOnMain(false)
                return
            }
            let serverData = serverData ?? [String: [String: Any]]()
            let groupsInApp = self.allGroups
            let groupIDsInApp = Set(groupsInApp.keys)
            let groupIDsFromServer = Set(serverData.keys.map{ UUID(uuidString: $0)! })

            let newGroupIDs = groupIDsFromServer.subtracting(groupIDsInApp)
            let mutualGroupIDs = groupIDsInApp.intersection(groupIDsFromServer)
            let deletedGroupIDs = groupIDsInApp.subtracting(groupIDsFromServer)

            self.log.debug("number of groups to be added to db: \(newGroupIDs.count)")
            self.log.debug("number of existing groups in db: \(mutualGroupIDs.count)")
            self.log.debug("number of groups to be deleted from db: \(deletedGroupIDs.count)")
            self.log.debug("------------------------------------------------")

            for groupID in newGroupIDs {
                let groupData = serverData[groupID.string]!
                let (members, publicKeys) = self.processMembershipData(from: groupData["members"] as! [[String: String]])
                let (groupKey, signingKey) = try! self.buildGroupKey(forGroupID: groupID, from: groupData["key"] as! String, signedByOneOf: publicKeys)
                let groupName = try! groupKey.decrypt(groupData["name"] as! String, signedBy: groupKey)
                let group = Group(uuid: groupID, name: groupName, fingerprint: groupKey.fingerprint, members: Set(members), album: Album())

                if signingKey != self.primaryUserKey {
                    let groupKeyCipher = self.encryptAndSignWithPrimaryUserKey(groupKey.private)
                    let dispatchGroup = DispatchGroup()
                    dispatchGroup.enter()
                    groupAPI.joinGroup(id: groupID, groupKeyCipher: groupKeyCipher, callbackOn: .global()) { [weak self] success in
                        defer {
                            dispatchGroup.leave()
                        }
                        guard let self = self else {
                            return
                        }
                        do {
                            guard success else { throw NSError(domain: "", code: 0, userInfo: nil) }
                            try self.add(group)
                            self.groupControllerDelegate?.joined(group)
                        } catch {
                            try? self.delete(key: groupKey)
                            self.log.error(String(describing: error))
                        }
                    }
                    dispatchGroup.wait()
                } else {
                    do {
                        try self.add(group)
                        self.groupControllerDelegate?.setup(group)
                    } catch {
                        try? self.delete(key: groupKey)
                        self.log.error(String(describing: error))
                        assertionFailure()
                    }
                }
            }

            for groupID in mutualGroupIDs {
                let group = groupsInApp[groupID]!
                let groupDataFromServer = serverData[groupID.string]!
                if !self.verifyKey(for: group, keyString: groupDataFromServer["key"] as! String) {
                    fatalError("group key verification failed. groupid: \(group.uuid.string)")
                }
                let localMemberIDs = Set(group.members.map{ $0.uuid })
                let remoteMembers = (groupDataFromServer["members"] as! [[String: String]]).reduce(into: [String: String]()) {
                    $0[$1["uuid"]!] = $1["key"]!
                }
                let remoteMemberIDs = Set(remoteMembers.keys.map{ UUID(uuidString: $0)! })
                if localMemberIDs != remoteMemberIDs {
                    self.sync(remoteMembers, with: group)
                }
            }

            for groupID in deletedGroupIDs {
                let group = groupsInApp[groupID]!
                do {
                    try self.remove(group)
                    self.groupControllerDelegate?.tearDown(group)
                    if let groupKey = self.groupKey(for: group) {
                        try self.delete(key: groupKey)
                    }
                } catch {
                    self.log.error(String(describing: error))
                    assertionFailure()
                }
            }
            callbackOnMain(true)
        }
    }

    func refreshGroupAlbums(callback: ClosureBool? = nil) {
        let callbackOnMain = { (continueNetworkOps: Bool) in
            if let callback = callback {
                DispatchQueue.main.async {
                    callback(continueNetworkOps)
                }
            }
        }
        guard let groupAPI = groupAPI else {
            callbackOnMain(false)
            return
        }
        groupAPI.fetchAlbumsForAllGroups(callbackOn: databaseQueue) { [weak self] (success: Bool, serverData: [String: [String: [String]]]?) in
            guard let self = self, success else {
                callbackOnMain(false)
                return
            }
            let serverData = serverData ?? [String: [String: [String]]]()
            let allGroups = self.allGroups
            for (groupIDstring, albumData) in serverData {
                guard let groupID = UUID(uuidString: groupIDstring) else {
                    self.log.error("invalid groupid - groupid: \(groupIDstring)")
                    assertionFailure()
                    continue
                }
                guard let assetIDs = albumData["assetids"]?.compactMap({ UUID(uuidString: $0) }) else {
                    self.log.error("missing assetids from server data - groupid: \(groupID)")
                    assertionFailure()
                    continue
                }
                assert(assetIDs.count == albumData["assetids"]?.count)
                guard let sharedAssetIDs = albumData["sharedassetids"]?.compactMap({ UUID(uuidString: $0) }) else {
                    self.log.error("missing sharedassetids from server data - groupid: \(groupID)")
                    assertionFailure()
                    continue
                }
                assert(sharedAssetIDs.count == albumData["sharedassetids"]?.count)
                guard let group = allGroups[groupID] else {
                    self.log.error("group missing from device - groupid: \(groupID)")
                    assertionFailure()
                    continue
                }
                if (Set(group.album.allAssets.keys) != Set(assetIDs)) || (Set(group.album.sharedAssets.keys) != Set(sharedAssetIDs)) {
                    do {
                        try self.update(group, assetIDs: assetIDs, sharedAssetIDs: sharedAssetIDs)
                    } catch {
                        self.log.error("groupid: \(groupID), error: \(String(describing: error))")
                        assertionFailure()
                    }
                }
            }
            callbackOnMain(true)
        }
    }

    func refreshUsers(for group: Group, callback: ClosureBool? = nil) {
        groupAPI?.fetchUsersInGroup(id: group.uuid, callbackOn: databaseQueue) { [weak self] (success: Bool, data: [String: String]?) in
            guard success else {
                callback?(false)
                return
            }
            self?.sync(data ?? [String: String](), with: group)
            callback?(true)
        }
    }

    private func processMembershipData(from groupData: [[String: String]]) -> ([User], [CryptoPublicKey]) {
        var members = [User]()
        var publicKeys = [primaryUserKey as CryptoPublicKey]
        for memberData in groupData {
            let uuid = UUID(uuidString: memberData["uuid"]!)!
            if let user = user(for: uuid) {
                members.append(user)
                publicKeys.append(try! keychain.retrievePublicKey(withFingerprint: user.fingerprint, keyType: .user)!)
            } else {
                var key: CryptoPublicKey!
                do {
                    key = try keychain.createPublicKey(for: .user, from: memberData["key"]!, saveToKeychain: true)
                } catch KeychainError.duplicate(.key) {
                    do {
                        key = try keychain.createPublicKey(for: .user, from: memberData["key"]!, saveToKeychain: false)
                    } catch {
                        fatalError(String(describing: error))
                    }
                } catch {
                    fatalError(String(describing: error))
                }
                let user = User(uuid: uuid, fingerprint: key.fingerprint, localContact: nil)
                try! add(user)
                members.append(user)
                publicKeys.append(key)
            }
        }
        return (members, publicKeys)
    }

    private func sync(_ userData: [String: String], with group: Group) {
        var usersInApp = allUsers
        let userIDsFromServer = Set(userData.keys.map{ UUID(uuidString: $0)! })
        let unknownMembers = userIDsFromServer.subtracting(usersInApp.keys)

        for userID in unknownMembers {
            let key = try! self.keychain.createPublicKey(for: .user, from: userData[userID.string]!, saveToKeychain: true)
            let user = User(uuid: userID, fingerprint: key.fingerprint, localContact: nil)
            try! add(user)
            usersInApp[userID] = user
        }

        let usersFromServer = Set(userIDsFromServer.map{ usersInApp[$0]! })
        let usersAddedToGroup = usersFromServer.subtracting(group.members)
        let usersRemovedFromGroup = group.members.subtracting(usersFromServer)
        if usersRemovedFromGroup.isNotEmpty {
            try! self.remove(usersRemovedFromGroup, from: group)
        }
        if usersAddedToGroup.isNotEmpty {
            try! self.add(usersAddedToGroup, to: group)
        }
    }
}

private extension ModelController {
    private func buildGroupKey(forGroupID groupID: UUID, from keyString: String, signedByOneOf publicKeys: [CryptoPublicKey]) throws -> (CryptoPrivateKey, CryptoPublicKey) {
        let (groupKeyString, signingKey) = try! primaryUserKey.decrypt(keyString, signedByOneOf: publicKeys)
        var key: CryptoPrivateKey!
        do {
            key = try keychain.createPrivateKey(for: .group, from: groupKeyString, password: nil, saveToKeychain: true)
        } catch KeychainError.duplicate(.key) where group(for: groupID) == nil {
            key = try keychain.createPrivateKey(for: .group, from: groupKeyString, password: nil, saveToKeychain: false)
        }
        return (key, signingKey)
    }

    private func verifyKey(for group: Group, keyString: String) -> Bool {
        var groupKeyString: String!
        do {
            groupKeyString = try primaryUserKey.decrypt(keyString, signedBy: primaryUserKey)
        } catch {
            log.error("error decrypting group key. groupID: \(group.uuid.string), error: \(error.localizedDescription)")
            return false
        }
        let groupKeyInApp = groupKey(for: group)!
        let groupKeyFromServer = try! keychain.createPrivateKey(for: .group, from: groupKeyString, password: nil, saveToKeychain: false)
        return groupKeyInApp == groupKeyFromServer
    }

    private func delete(key: CryptoPrivateKey) throws {
        try keychain.deletePrivateKey(key)
    }

    private func generateNewKey(for keyType: KeyType) -> CryptoPrivateKey {
        return keychain.generateNewPrivateKey(keyType, passwordProtected: false, saveToKeychain: true)
    }

    private func encryptAndSignWithPrimaryUserKey(_ string: String) -> String {
        return primaryUserKey.encrypt(string, signed: primaryUserKey)
    }

    private func groupKey(for group: Group) -> CryptoPrivateKey? {
        return try? keychain.retrievePrivateKey(withFingerprint: group.fingerprint, keyType: .group)
    }

    private func encryptAndSign(_ plainText: String, for user: User) throws -> String {
        let userKey = try keychain.retrievePublicKey(withFingerprint: user.fingerprint, keyType: .user)!
        return userKey.encrypt(plainText, signed: primaryUserKey)
    }
}

extension ModelController: GroupFinder {
    var allGroups: [UUID: Group] {
        return groupDatabase.allGroups
    }

    func group(for id: UUID) -> Group? {
        return groupDatabase.lookup(id)
    }
}

extension ModelController: GroupCreator {
    func createGroup(name: String, callback: @escaping (Bool, Group?) -> Void) {
        let groupKey = generateNewKey(for: .group)
        let encryptedName = groupKey.encrypt(name, signed: groupKey)
        let encryptedKey = encryptAndSignWithPrimaryUserKey(groupKey.private)
        groupAPI?.createGroup(name: encryptedName, keyStringCipher: encryptedKey, callbackOn: databaseQueue) { [weak self] (success, groupID) in
            do {
                guard let self = self, success, let groupID = groupID else { throw NSError(domain: "", code: 0, userInfo: nil) }
                let group = Group(uuid: groupID, name: name, fingerprint: groupKey.fingerprint, members: Set<User>(), album: Album())
                try self.add(group)
                self.groupControllerDelegate?.setup(group)
                DispatchQueue.main.async {
                    callback(true, group)
                }
            } catch {
                try? self?.delete(key: groupKey)
                self?.log.error(String(describing: error))
                DispatchQueue.main.async {
                    callback(false, nil)
                }
            }
        }
    }
}

extension ModelController: GroupDestroyer {
    func leaveGroup(_ group: Group, callback: @escaping ClosureBool) {
        groupAPI?.leaveGroup(id: group.uuid, callbackOn: databaseQueue) { [weak self] success in
            do {
                guard let self = self, success else { throw NSError(domain: "", code: 0, userInfo: nil) }
                try self.remove(group)
                self.groupControllerDelegate?.left(group)
                if let groupKey = self.groupKey(for: group) {
                    try? self.delete(key: groupKey)
                }
                DispatchQueue.main.async {
                    callback(true)
                }
            } catch {
                self?.log.error(String(describing: error))
                DispatchQueue.main.async {
                    callback(false)
                }
            }
        }
    }
}

extension ModelController: GroupManager {
    func addUsers<T>(_ users: T, to group: Group, callback: @escaping ClosureBool) where T: Collection, T.Element == User {
        guard let groupKey = groupKey(for: group) else { DispatchQueue.main.async { callback(false) }; return }
        var groupInvites = [(id: UUID, groupKeyCipher: String)]()
        for user in users {
            do {
                groupInvites.append((id: user.uuid, groupKeyCipher: try encryptAndSign(groupKey.private, for: user)))
            } catch {
                log.error(String(describing: error))
                assertionFailure()
            }
        }
        guard groupInvites.isNotEmpty else { DispatchQueue.main.async { callback(false) }; return }
        groupAPI?.amendGroup(id: group.uuid, invites: groupInvites, callbackOn: databaseQueue) { [weak self] success in
            do {
                guard let self = self, success else { throw NSError(domain: "", code: 0, userInfo: nil) }
                try self.add(users, to: group)
                self.groupControllerDelegate?.inviteSent(to: users)
                DispatchQueue.main.async {
                    callback(true)
                }
            } catch {
                self?.log.error(String(describing: error))
                DispatchQueue.main.async {
                    callback(false)
                }
            }
        }
    }

    func addAssets<T>(_ assets: T, to group: Group, share: Bool, callback: @escaping ClosureBool) where T: Collection, T.Element == Asset {
        assetImportManager?.priorityImport(assets) { [weak self] success in
            guard let self = self, let groupAPI = self.groupAPI, success else {
                DispatchQueue.main.async {
                    callback(false)
                }
                return
            }
            groupAPI.amendGroup(id: group.uuid, add: true, assetIDs: assets.map{ $0.uuid }, callbackOn: self.databaseQueue) { [weak self] success in
                do {
                    guard let self = self, success else { throw NSError(domain: "", code: 0, userInfo: nil) }
                    try self.add(assets, to: group)
                    if share, let group = self.group(for: group.uuid) { // refresh group variable – changed due to this amend function
                        self.shareAssets(assets, withGroup: group, callback: callback)
                    } else {
                        DispatchQueue.main.async {
                            callback(true)
                        }
                    }
                } catch {
                    self?.log.error(String(describing: error))
                    DispatchQueue.main.async {
                        callback(false)
                    }
                }
            }
        }
    }

    func removeAssets<T>(_ assets: T, from group: Group, callback: @escaping ClosureBool) where T: Collection, T.Element == Asset {
        groupAPI?.amendGroup(id: group.uuid, add: false, assetIDs: assets.map{ $0.uuid }, callbackOn: databaseQueue) { [weak self] success in
            do {
                guard let self = self, success else { throw NSError(domain: "", code: 0, userInfo: nil) }
                try self.remove(assets, from: group)
                if Set(group.album.sharedAssets.values).intersection(assets).isNotEmpty {
                    self.groupControllerDelegate?.assetsChanged(for: group)
                }
                DispatchQueue.main.async {
                    callback(true)
                }
            } catch {
                self?.log.error(String(describing: error))
                DispatchQueue.main.async {
                    callback(false)
                }
            }
        }
    }

    func shareAssets<T>(_ assets: T, withGroup group: Group, callback: @escaping ClosureBool) where T: Collection, T.Element == Asset {
        let assetIDs = assets.map{ $0.uuid }
        guard let publicKey = groupKey(for: group) else { DispatchQueue.main.async { callback(false) }; return }
        assetShareManager?.encryptAssetKeys(withKey: publicKey, forAssetsWithIDs: assetIDs) { [weak self] (success, keyStrings) in
            guard let self = self, success else { DispatchQueue.main.async { callback(false) }; return }
            self.groupAPI?.amendGroup(id: group.uuid, share: true, assetIDs: assetIDs, keyStringsForAssets: keyStrings, callbackOn: self.databaseQueue) { [weak self] success in
                do {
                    guard let self = self, success else { throw NSError(domain: "", code: 0, userInfo: nil) }
                    try self.share(assets, with: group)
                    self.groupControllerDelegate?.assetsChanged(for: group)
                    DispatchQueue.main.async {
                        callback(true)
                    }
                } catch {
                    self?.log.error(String(describing: error))
                    DispatchQueue.main.async {
                        callback(false)
                    }
                }
            }
        }
    }

    func unshareAssets<T>(_ assets: T, fromGroup group: Group, callback: @escaping ClosureBool) where T: Collection, T.Element == Asset {
        groupAPI?.amendGroup(id: group.uuid, share: false, assetIDs: assets.map{ $0.uuid }, keyStringsForAssets: nil, callbackOn: databaseQueue) { [weak self] success in
            do {
                guard let self = self, success else { throw NSError(domain: "", code: 0, userInfo: nil) }
                try self.unshare(assets, from: group)
                self.groupControllerDelegate?.assetsChanged(for: group)
                DispatchQueue.main.async {
                    callback(true)
                }
            } catch {
                self?.log.error(String(describing: error))
                DispatchQueue.main.async {
                    callback(false)
                }
            }
        }
    }
}
