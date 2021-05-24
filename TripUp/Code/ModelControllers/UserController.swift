//
//  UserController.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 30/09/2019.
//  Copyright © 2019 Vinoth Ramiah. All rights reserved.
//

import Foundation

protocol UserFinder {
    var allUsers: [UUID: User] { get }
    func user(for id: UUID) -> User?
}

protocol UserCreator {
    func add(_ user: User) throws
    func add<T>(_ users: T) throws where T: Collection, T.Element == User
}

protocol UserManager: UserFinder, UserCreator, UserObserverRegister {
    func update(preselectedContacts: [Contact]?)
    func refreshUsers(preselectedContacts: [Contact]?, callback: ClosureBool?)
    func retrieveUserFromServer(uuid: UUID, callback: @escaping ((User, CryptoPublicKey)?) -> Void)
}

protocol UserAPI {
    func verify<T>(userIDs: T, callbackOn queue: DispatchQueue, callback: @escaping (Bool, [String]?) -> Void) where T: Sequence, T.Element == UUID
    func findUser(uuid: String, callbackOn queue: DispatchQueue, callback: @escaping (String?) -> Void)
    func findUsers(uuids: [String], numbers: [String], emails: [String], callbackOn queue: DispatchQueue, callback: @escaping (Bool, [String: [String : Any]]?) -> Void)
}

extension ModelController {
    func remove(_ user: User) throws {
        try remove([user])
    }

    func remove<T>(_ users: T) throws where T: Collection, T.Element == User {
        let groups = allGroups
        let updatedGroups = try userDatabase.remove(userIDs: users.map{ $0.uuid })
        observers(notify: .removed(Set(users)))
        for updatedGroup in updatedGroups {
            guard let group = groups[updatedGroup.uuid] else { assertionFailure(updatedGroup.uuid.string); continue }
            observers(notify: .updated(group, to: updatedGroup))
        }
    }

    func update(contact: Contact?, for user: User) throws {
        let groups = allGroups
        let (updatedUser, updatedGroups) = try userDatabase.update(try? JSONEncoder().encode(contact), forUserID: user.uuid)
        observers(notify: .updated(updatedUser))
        for updatedGroup in updatedGroups {
            guard let group = groups[updatedGroup.uuid] else { assertionFailure(updatedGroup.uuid.string); continue }
            observers(notify: .updated(group, to: updatedGroup))
        }
    }
}

extension ModelController: UserFinder {
    var allUsers: [UUID: User] {
        return userDatabase.allUsers
    }

    func user(for id: UUID) -> User? {
        return userDatabase.lookup(id)
    }
}

extension ModelController: UserCreator {
    func add(_ user: User) throws {
        try add([user])
    }

    func add<T>(_ users: T) throws where T: Collection, T.Element == User {
        try userDatabase.add(users)
        observers(notify: .new(Set(users)))
    }
}

extension ModelController: UserManager {
    func update(preselectedContacts: [Contact]? = nil) {
    }
    func refreshUsers(preselectedContacts: [Contact]? = nil, callback: ClosureBool? = nil) {
        let callbackOnMain = { (continueNetworkOps: Bool) in
            if let callback = callback {
                DispatchQueue.main.async {
                    callback(continueNetworkOps)
                }
            }
        }
        databaseQueue.async { [weak self] in
            guard let self = self else {
                callbackOnMain(false)
                return
            }
            let allUsers = self.allUsers
            let uuids = allUsers.keys.map{ $0.string }
            var numberHashesToContacts = [String: Contact]()
            var emailHashesToContacts = [String: Contact]()

            if let preselectedContacts = preselectedContacts {
                let contactsSorted = preselectedContacts.sorted(by: { $0.localID > $1.localID })   // sort for deterministic elminiation of duplicates being sent to server
                for contact in contactsSorted {
                    let hash = contact.addressable.sha256()
                    switch contact.type {
                    case .number:
                        numberHashesToContacts[hash] = contact
                    case .email:
                        emailHashesToContacts[hash] = contact
                    }
                }
            }

            if self.contactManager.authorized {
                let contacts = self.contactManager.allContacts
                if contacts.isNotEmpty {
                    let contactsSorted = contacts.sorted(by: { $0.localID > $1.localID })   // sort for deterministic elminiation of duplicates being sent to server
                    for contact in contactsSorted {
                        let hash = contact.addressable.sha256()
                        switch contact.type {
                        case .number:
                            numberHashesToContacts[hash] = contact
                        case .email:
                            emailHashesToContacts[hash] = contact
                        }
                    }
                }
                // prune stale contact info from user db
                for user in allUsers.values {
                    guard let contact = user.localContact else { continue }
                    if !contacts.contains(contact) {
                        do {
                            try self.update(contact: nil, for: user)
                        } catch {
                            self.log.error("\(String(describing: error)) – user: \(String(describing: user)), contact: \(String(describing: contact))")
                            return  // return because later number/email matching depends on this data being up to date
                        }
                    }
                }
            }

            guard uuids.isNotEmpty || numberHashesToContacts.isNotEmpty || emailHashesToContacts.isNotEmpty else {
                callbackOnMain(true)
                return
            }
            self.userAPI?.findUsers(uuids: uuids, numbers: Array(numberHashesToContacts.keys), emails: Array(emailHashesToContacts.keys), callbackOn: self.databaseQueue) { [weak self] (success, serverData) in
                guard let self = self, success else {
                    callbackOnMain(false)
                    return
                }
                let serverData = serverData ?? [String: [String : Any]]()

                let clientUsers = self.allUsers
                let uuidsFromServer = serverData["uuids"] as! [String: String]
                var usersToRemove = [User]()
                var clientUsersRemaining = clientUsers
                for (uuid, user) in clientUsers {
                    if let _ = uuidsFromServer[uuid.string] {
                        // TODO: verify publicKey, warn user if key has changed
                    } else {
                        usersToRemove.append(user)
                        clientUsersRemaining[uuid] = nil
                    }
                }
                if usersToRemove.isNotEmpty {
                    do {
                        try self.remove(usersToRemove)
                    } catch {
                        self.log.error("\(String(describing: error)) – usersToRemove: \(String(describing: usersToRemove))")
                        assertionFailure()
                        return  // return because later number/email matching depends on this data being up to date
                    }
                }

                var newUsers = [User]()
                for (hash, userData) in serverData["otherIdentifiers"] as! [String: [String: String]] {
                    guard let uuidString = userData["uuid"], let uuid = UUID(uuidString: uuidString) else {
                        self.log.error("found invalid uuid – userData: \(userData)")
                        assertionFailure()
                        continue
                    }
                    guard let contact = numberHashesToContacts[hash] ?? emailHashesToContacts[hash] else {
                        self.log.error("hash not recognised – uuid: \(uuidString), hash: \(hash)")
                        assertionFailure()
                        continue
                    }
                    if let user = clientUsersRemaining[uuid] {    // user<->contact linking
                        guard user.localContact == nil else {
                            continue
                        }
                        do {
                            try self.update(contact: contact, for: user)
                        } catch {
                            self.log.error("\(String(describing: error)) – uuid: \(uuidString), contact: \(String(describing: contact))")
                        }
                    } else {    // new users
                        guard let publicKeyString = userData["publicKey"] else {
                            self.log.error("publicKey missing – uuid: \(uuidString), contact: \(String(describing: contact))")
                            assertionFailure()
                            continue
                        }
                        var publicKey: CryptoPublicKey!
                        do {
                            publicKey = try self.keychain.createPublicKey(for: .user, from: publicKeyString, saveToKeychain: false)
                            try self.keychain.savePublicKey(publicKey)
                        } catch KeychainError.duplicate(.key) {
                        } catch {
                            self.log.error("\(String(describing: error)) – uuid: \(uuidString), contact: \(String(describing: contact)), publicKey: \(publicKeyString)")
                            assertionFailure()
                            continue
                        }
                        newUsers.append(User(uuid: uuid, fingerprint: publicKey.fingerprint, localContact: contact))
                    }
                }
                if newUsers.isNotEmpty {
                    do {
                        try self.add(newUsers)
                    } catch {
                        self.log.error("\(String(describing: error)) – newUsers: \(String(describing: newUsers))")
                        assertionFailure()
                    }
                }
                callbackOnMain(true)
            }
        }
    }

    func retrieveUserFromServer(uuid: UUID, callback: @escaping ((User, CryptoPublicKey)?) -> Void) {
        databaseQueue.async { [weak self] in
            let callbackOnMain = { (userWithKey: (User, CryptoPublicKey)?) in
                DispatchQueue.main.async {
                    callback(userWithKey)
                }
            }
            guard let userAPI = self?.userAPI else {
                callbackOnMain(nil)
                return
            }
            userAPI.findUser(uuid: uuid.string, callbackOn: .global()) { [weak self] publicKeyString in
                guard let self = self else {
                    callbackOnMain(nil)
                    return
                }
                guard let publicKeyString = publicKeyString, publicKeyString.isNotEmpty else {
                    self.log.debug("publicKey not found or is empty - userID: \(uuid)")
                    callbackOnMain(nil)
                    return
                }
                do {
                    let publicKey = try self.keychain.createPublicKey(for: .user, from: publicKeyString, saveToKeychain: false)
                    let user = User(uuid: uuid, fingerprint: publicKey.fingerprint, localContact: nil)
                    callbackOnMain((user, publicKey))
                } catch {
                    self.log.error("error retrieving user from server - userID: \(uuid), publicKey: \(publicKeyString), error: \(String(describing: error))")
                    callbackOnMain(nil)
                }
            }
        }
    }
}
