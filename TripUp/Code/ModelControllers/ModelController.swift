//
//  ModelController.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 06/11/2020.
//  Copyright © 2020 Vinoth Ramiah. All rights reserved.
//

import Foundation

protocol AssetObserver: AnyObject {
    func new(_ assets: Set<Asset>)
    func deleted(_ assets: Set<Asset>)
    func updated(_ oldAsset: Asset, to newAsset: Asset)
}

extension AssetObserver {
    func new(_ assets: Set<Asset>) {}
    func deleted(_ assets: Set<Asset>) {}
    func updated(_ oldAsset: Asset, to newAsset: Asset) {}
}

protocol AssetObserverRegister {
    func addObserver(_ observer: AssetObserver)
    func removeObserver(_ observer: AssetObserver)
}

protocol GroupObserver: AnyObject {
    func new(_ group: Group)
    func updated(_ oldGroup: Group, to newGroup: Group)
    func deleted(_ group: Group)
}

extension GroupObserver {
    func new(_ group: Group) {}
    func updated(_ oldGroup: Group, to newGroup: Group) {}
    func deleted(_ group: Group) {}
}

protocol GroupObserverRegister {
    func addObserver(_ observer: GroupObserver)
    func removeObserver(_ observer: GroupObserver)
}

protocol UserObserver: AnyObject {
    func new(_ users: Set<User>)
    func removed(_ users: Set<User>)
    func updated(_ user: User)
}

extension UserObserver {
    func new(_ users: Set<User>) {}
    func removed(_ users: Set<User>) {}
    func updated(_ user: User) {}
}

protocol UserObserverRegister {
    func addObserver(_ observer: UserObserver)
    func removeObserver(_ observer: UserObserver)
}

class ModelController {
    enum AssetsUpdate {
        case new(Set<Asset>)
        case deleted(Set<Asset>)
        case updated(Asset, Asset)
    }

    enum GroupsUpdate {
        case new(Group)
        case updated(Group, to: Group)
        case deleted(Group)
    }

    enum UsersUpdate {
        case new(Set<User>)
        case removed(Set<User>)
        case updated(User)
    }

    private struct AssetObserverWrapper {
        weak var observer: AssetObserver?
    }

    private struct GroupObserverWrapper {
        weak var observer: GroupObserver?
    }

    private struct UserObserverWrapper {
        weak var observer: UserObserver?
    }

    let log = Logger.self
    let databaseQueue = DispatchQueue(label: String(describing: ModelController.self))
    let contactManager: ContactsProvider = ContactsManager()
    unowned let assetDatabase: AssetDatabase
    unowned let groupDatabase: GroupDatabase
    unowned let userDatabase: UserDatabase

    weak var groupControllerDelegate: GroupControllerDelegate?
    weak var assetImportManager: AssetImportManager?
    weak var assetShareManager: AssetShareManager?
    weak var assetSyncManager: AssetSyncManager?
    /*weak*/ var groupAPI: GroupAPI?
    /*weak*/ var userAPI: UserAPI?
    /*weak*/ var assetAPI: AssetAPI?
    /*weak*/ var keychain: Keychain<CryptoPublicKey, CryptoPrivateKey>!
    var primaryUserID: UUID!
    var primaryUserKey: CryptoPrivateKey!

    private var assetObservers = [ObjectIdentifier: AssetObserverWrapper]()
    private var groupObservers = [ObjectIdentifier: GroupObserverWrapper]()
    private var userObservers = [ObjectIdentifier: UserObserverWrapper]()

    init(assetDatabase: AssetDatabase, groupDatabase: GroupDatabase, userDatabase: UserDatabase) {
        self.assetDatabase = assetDatabase
        self.groupDatabase = groupDatabase
        self.userDatabase = userDatabase
    }

    func observers(notify: AssetsUpdate) {
        DispatchQueue.main.async {
            for (id, observerWrapper) in self.assetObservers {
                guard let observer = observerWrapper.observer else {
                    self.assetObservers.removeValue(forKey: id)
                    continue
                }
                switch notify {
                case .new(let assets):
                    observer.new(assets)
                case .deleted(let assets):
                    observer.deleted(assets)
                case .updated(let oldAsset, let newAsset):
                    observer.updated(oldAsset, to: newAsset)
                }
            }
        }
    }

    func observers(notify: GroupsUpdate) {
        DispatchQueue.main.async {
            for (id, observerWrapper) in self.groupObservers {
                guard let observer = observerWrapper.observer else {
                    self.groupObservers.removeValue(forKey: id)
                    continue
                }
                switch notify {
                case .new(let group):
                    observer.new(group)
                case .updated(let group, let newGroup):
                    observer.updated(group, to: newGroup)
                case .deleted(let group):
                    observer.deleted(group)
                }
            }
        }
    }

    func observers(notify: UsersUpdate) {
        DispatchQueue.main.async {
            for (id, observerWrapper) in self.userObservers {
                guard let observer = observerWrapper.observer else {
                    self.userObservers.removeValue(forKey: id)
                    continue
                }
                switch notify {
                case .new(let users):
                    observer.new(users)
                case .removed(let users):
                    observer.removed(users)
                case .updated(let user):
                    observer.updated(user)
                }
            }
        }
    }
}

extension ModelController: AssetObserverRegister {
    func addObserver(_ observer: AssetObserver) {
        assert(Thread.isMainThread)
        let id = ObjectIdentifier(observer)
        assetObservers[id] = AssetObserverWrapper(observer: observer)
    }

    func removeObserver(_ observer: AssetObserver) {
        assert(Thread.isMainThread)
        let id = ObjectIdentifier(observer)
        assetObservers.removeValue(forKey: id)
    }
}

extension ModelController: GroupObserverRegister {
    func addObserver(_ observer: GroupObserver) {
        assert(Thread.isMainThread)
        let id = ObjectIdentifier(observer)
        groupObservers[id] = GroupObserverWrapper(observer: observer)
    }

    func removeObserver(_ observer: GroupObserver) {
        assert(Thread.isMainThread)
        let id = ObjectIdentifier(observer)
        groupObservers.removeValue(forKey: id)
    }
}

extension ModelController: UserObserverRegister {
    func addObserver(_ observer: UserObserver) {
        assert(Thread.isMainThread)
        let id = ObjectIdentifier(observer)
        userObservers[id] = UserObserverWrapper(observer: observer)
    }

    func removeObserver(_ observer: UserObserver) {
        assert(Thread.isMainThread)
        let id = ObjectIdentifier(observer)
        userObservers.removeValue(forKey: id)
    }
}
