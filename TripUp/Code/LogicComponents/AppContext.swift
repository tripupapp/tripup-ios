//
//  AppContext.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 03/09/2018.
//  Copyright © 2018 Vinoth Ramiah. All rights reserved.
//

import Foundation
import Photos
import UIKit.UIApplication

import TripUpShared

protocol DependencyInjector {
    func initialise(_ cloudStorageVC: CloudStorageVC)
    func initialise(_ mainVC: MainVC)
    func initialise(_ libraryVC: LibraryVC)
    func initialise(_ albumsVC: AlbumsVC)
    func initialise(_ newGroupVC: NewStreamView)
    func initialise(_ userSelectionVC: UserSelectionView)
    func initialise(preferencesView: PreferencesView)
    func initialise(authenticationView: AuthenticationView)
    func initialise(securityView: SecurityView)
    func initialise(photoView: PhotoView)
    func initialise(inAppPurchaseView: InAppPurchaseView)
}

protocol KeychainDelegate: class {
    var primaryUserKey: CryptoPrivateKey { get }
    func groupKey(for groupID: UUID) -> CryptoPrivateKey?
    func assetKey(forFingerprint assetFingerprint: String) -> CryptoPrivateKey?
    func newAssetKey() -> CryptoPrivateKey
    func delete(key: CryptoPrivateKey) throws
    func publicKey(type: KeyType, fingerprint: String) -> CryptoPublicKey?
    func privateKey(type: KeyType, fingerprint: String) -> CryptoPrivateKey?
    func privateKey(from keyString: String, of keyType: KeyType) throws -> CryptoPrivateKey
}

protocol AppContextInfo: AnyObject {
    var photoLibraryAccessDenied: Bool? { get }
    func usedStorage(callback: @escaping ((noOfItems: Int, totalSize: UInt64)) -> Void)
    func lowDiskSpace(callback: @escaping ClosureBool)
    func lowCloudStorage(callback: @escaping ClosureBool)
}

protocol AppContextObserver: AnyObject {
    func handle(status: AppContext.Status)
    func reload(inProgress: Bool)
}

extension AppContextObserver {
    func handle(status: AppContext.Status) {}
    func reload(inProgress: Bool) {}
}

protocol AppContextObserverRegister {
    func addObserver(_ observer: AppContextObserver)
    func removeObserver(_ observer: AppContextObserver)
}

extension AppContext: AppContextInfo {
    var photoLibraryAccessDenied: Bool? {
        if let photoLibraryAccess = photoLibrary.canAccess {
            return !photoLibraryAccess
        }
        return nil
    }
    
    func usedStorage(callback: @escaping ((noOfItems: Int, totalSize: UInt64)) -> Void) {
        modelController.cloudStorageUsed { (cloudStorage) in
            DispatchQueue.main.async {
                callback(cloudStorage)
            }
        }
    }

    func lowDiskSpace(callback: @escaping ClosureBool) {
        appDelegate.lowDiskSpace(callback: callback)
    }

    func lowCloudStorage(callback: @escaping ClosureBool) {
        purchasesController.entitled { [weak self] currentTier in
            DispatchQueue.main.async {
                if let self = self {
                    self.isLowOnCloudStorage(basedOn: currentTier, callback: callback)
                } else {
                    callback(true)
                }
            }
        }
    }
}

extension AppContext: DependencyInjector {
    func initialise(_ cloudStorageVC: CloudStorageVC) {
        cloudStorageVC.initialise(purchasesController: purchasesController)
    }

    func initialise(_ mainVC: MainVC) {
        mainVC.initialise(dependencyInjector: self)
    }

    func initialise(_ libraryVC: LibraryVC) {
        libraryVC.initialise(primaryUserID: primaryUser.uuid, assetFinder: modelController, assetObserverRegister: modelController, assetManager: assetManager, userFinder: modelController, appContextInfo: self, networkController: networkMonitor)
        addObserver(libraryVC)
    }

    func initialise(_ albumsVC: AlbumsVC) {
        albumsVC.initialise(groupManager: modelController, groupObserverRegister: modelController, assetManager: assetManager, networkController: networkMonitor, dependencyInjector: self)
        addObserver(albumsVC)
    }

    func initialise(_ newGroupVC: NewStreamView) {
        newGroupVC.initialise(groupManager: modelController, dependencyInjector: self)
    }

    func initialise(_ userSelectionVC: UserSelectionView) {
        userSelectionVC.initialise(primaryUser: primaryUser, userManager: modelController)
    }

    func initialise(preferencesView: PreferencesView) {
        preferencesView.initialise(primaryUser: primaryUser, apiUser: apiUser, appContextInfo: self, purchasesController: purchasesController, appDelegateExtension: appDelegate, dependencyInjector: self)
    }

    func initialise(authenticationView: AuthenticationView) {
        let loginLC = LoginLogicController(emailAuthFallbackURL: URL(string: appDelegate.config.appStoreURL)!)
        authenticationView.initialise(authUser: apiUser, loginLogicController: loginLC, api: webAPI)
    }

    func initialise(securityView: SecurityView) {
        securityView.initialise(primaryUser: primaryUser, keychain: keychain)
    }

    func initialise(photoView: PhotoView) {
        photoView.initialise(primaryUserID: primaryUser.uuid, groupManager: modelController, groupObserverRegister: modelController, assetManager: assetManager, userFinder: modelController, networkController: networkMonitor, appContextInfo: self, dependencyInjector: self)
        addObserver(photoView)
        purchasesController.addObserver(photoView)
    }

    func initialise(inAppPurchaseView: InAppPurchaseView) {
        inAppPurchaseView.initialise(purchasesController: purchasesController)
    }
}

extension AppContext: GroupControllerDelegate {
    func setup(_ group: Group) {}
    func tearDown(_ group: Group) {}
    func inviteSent<T>(to users: T) where T: Collection, T.Element == User {}
    func assetsChanged(for group: Group) {}

    func joined(_ group: Group) {
        DispatchQueue.main.async {
            guard !self.cloudReloadInProgress else {
                return
            }
            self.cloudReloadInProgress = true
            self.modelController.refreshAssets { [weak self] success in
                guard success else {
                    self?.cloudReloadInProgress = false
                    return
                }
                self?.modelController.refreshGroupAlbums { (_) in
                    self?.cloudReloadInProgress = false
                }
            }
        }
        setup(group)
    }

    func left(_ group: Group) {
        DispatchQueue.main.async {
            guard !self.cloudReloadInProgress else {
                return
            }
            self.cloudReloadInProgress = true
            self.modelController.refreshAssets { (_) in
                self.cloudReloadInProgress = false
            }
        }
        tearDown(group)
    }
}

class AppContext {
    var assetManager: AssetManager!
    private(set) var networkMonitor: NetworkMonitor?

    private let log = Logger.self

    private unowned let appDelegate: AppDelegate
    private var primaryUser: User {
        didSet {
            appDelegate.primaryUser = primaryUser
        }
    }
    private let webAPI: API
    private let apiUser: APIUser

    private let modelController: ModelController
    private let purchasesController: PurchasesController

    private let keychain: Keychain<CryptoPublicKey, CryptoPrivateKey>
    private let photoLibrary = PhotoLibrary()

    private var contextObservers = [ObjectIdentifier: AppContextObserverWrapper]()
    private var cloudReloadInProgress: Bool = false

    init(user: User, apiUser: APIUser, webAPI: API, keychain: Keychain<CryptoPublicKey, CryptoPrivateKey>, database: Database, config: AppConfig, purchasesController: PurchasesController, dataService: DataService, appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        self.apiUser = apiUser
        self.webAPI = webAPI
        self.keychain = keychain

        let primaryUserKey = try! keychain.retrievePrivateKey(withFingerprint: user.fingerprint, keyType: .user)!

        modelController = ModelController(assetDatabase: database, groupDatabase: database, userDatabase: database)
        modelController.groupAPI = webAPI
        modelController.userAPI = webAPI
        modelController.assetAPI = webAPI
        modelController.keychain = keychain
        modelController.primaryUserID = user.uuid
        modelController.primaryUserKey = primaryUserKey

        // use primary user info from database if possible, otherwise use injected user and save injected user to the database
        if let primaryUser = modelController.user(for: user.uuid) {
            self.primaryUser = primaryUser
        } else {
            self.primaryUser = user
            try! modelController.add(primaryUser)
        }

        self.purchasesController = purchasesController
        purchasesController.addObserver(self)

//        let dataManager = DataManager(dataService: dataService, simultaneousTransfers: 4)
        self.assetManager = AssetManager(assetController: modelController, assetDatabase: modelController, photoLibrary: photoLibrary, keychainDelegate: self, apiUser: apiUser, webAPI: webAPI, dataService: dataService, networkController: networkMonitor)
        assetManager.triggerStatusNotification = { [weak self] in
            self?.generateStatusNotification()
        }
        addObserver(assetManager)
        modelController.assetImportManager = assetManager
        modelController.assetShareManager = assetManager
        modelController.assetSyncManager = assetManager
        modelController.groupControllerDelegate = self
        modelController.addObserver(self)

        networkMonitor = NetworkMonitor(host: config.apiBaseURL, apiUser: apiUser)
        networkMonitor?.addObserver(self)
    }

    func handle(url: URL) -> Bool {
        if handleEmailAuth(link: url) {
            return true
        } else {
            let handled = UniversalLinksService.shared.handle(link: url) { (universalLink) in
                if let universalLink = universalLink {
                    self.handle(universalLink: universalLink)
                }
            }
            return handled
        }
    }

    private func handle(universalLink: UniversalLinksService.UniversalLink) {
        switch universalLink {
        case .user(let userID):
            guard userID != primaryUser.uuid else {
                appDelegate.window?.makeToastie("TripUp knows who you are already 😉", duration: 7.0, position: .center)
                return
            }
            if let user = modelController.user(for: userID) {
                appDelegate.window?.makeToastie("Tripper with ID suffix \(user.uuid.string.suffix(4)) has already been added 👍", duration: 7.0, position: .center)
            } else {
                modelController.retrieveUserFromServer(uuid: userID) { [weak self] (userWithKey) in
                    var success = false
                    if let user = userWithKey?.0, let userKey = userWithKey?.1 {
                        var saved = false
                        do {
                            try self?.keychain.savePublicKey(userKey)
                            saved = true
                        } catch KeychainError.duplicate(.key) {
                            saved = true
                        } catch {
                            self?.log.error("unable to save public key - userID: \(userID), publicKey: \(String(describing: userKey)), error: \(String(describing: error))")
                            assertionFailure()
                        }
                        if saved {
                            do {
                                try self?.modelController.add(user)
                                success = true
                            } catch {
                                try? self?.keychain.deletePublicKey(userKey)
                                self?.log.error("failed to add user to local database - userID: \(userID), error: \(String(describing: error))")
                                assertionFailure()
                            }
                        }
                    }
                    if success {
                        let alertController = UIAlertController(title: "Found Tripper with ID suffix \(userID.string.suffix(4)) 🙌", message: "You can add this Tripper to shared albums now", preferredStyle: .alert)
                        alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                        self?.appDelegate.window?.rootViewController?.present(alertController, animated: true, completion: nil)
                    } else {
                        self?.appDelegate.window?.makeToastie("Failed to retrieve Tripper details 😞. Please try again", duration: 10.0, position: .center)
                    }
                }
            }
        }
    }

    private func handleEmailAuth(link: URL) -> Bool {
        let loginLogicController = LoginLogicController(emailAuthFallbackURL: URL(string: appDelegate.config.appStoreURL)!)
        guard loginLogicController.isSignIn(link: link) else { return false }
        guard let loginProgressEncoded = UserDefaults.standard.data(forKey: UserDefaultsKey.LoginInProgress.rawValue), let email = String(data: loginProgressEncoded, encoding: .utf8) else { return false }
        loginLogicController.link(email: email, withLink: link, toUser: apiUser, api: webAPI) { [weak self] success in
            guard let self = self else { return }
            UserDefaults.standard.removeObject(forKey: UserDefaultsKey.LoginInProgress.rawValue)
            if success {
                self.appDelegate.window?.makeToastie("Email validation was successful!", duration: 5.0, position: .center)
            } else {
                self.appDelegate.window?.makeToastie("There was an issue when verifying your email address. Please try again.", duration: 10.0, position: .center)
            }
        }
        return true
    }

    static let soma = "VGhpcyBpcyBhIEdQTCBsaWNlbnNlZCBhcHBsaWNhdGlvbiBieSBWaW5vdGggUmFtaWFo"

    private func fetchAndConsolidateCloudData(callback: ((Result<Any?, Error>) -> Void)? = nil) {
        precondition(Thread.isMainThread)

        guard !cloudReloadInProgress else {
            callback?(.failure("network reload in progress already"))
            return
        }
        cloudReloadInProgress = true

        let reloadFinished = { [weak self] (result: Result<Any?, Error>) in
            precondition(Thread.isMainThread)
            self?.cloudReloadInProgress = false
            callback?(result)
        }
        modelController.refreshUsers { [weak self] success in
            guard let self = self, success else {
                reloadFinished(.failure("refresh users failed"))
                return
            }
            self.modelController.refreshGroups { [weak self] success in
                guard let self = self, success else {
                    reloadFinished(.failure("refresh groups failed"))
                    return
                }
                self.modelController.refreshAssets { [weak self] success in
                    guard let self = self, success else {
                        reloadFinished(.failure("refresh assets failed"))
                        return
                    }
                    self.modelController.refreshGroupAlbums { (success) in
                        reloadFinished(success ? .success(nil) : .failure("refresh group albums failed"))
                    }
                }
            }
        }
    }

    // Fetch from local device and cloud at same time
    // However, cloud fetch must update device before local consolidation with device library
    // After consolidation, if we're sure cloud info has been updated, we queue up pending imports/deletes etc
    private func fullContextUpdate() {
        precondition(Thread.isMainThread)
        let dispatchGroup = DispatchGroup()

        var photoLibraryFetchResult: ([PHAsset], [String])?
        dispatchGroup.enter()
        photoLibraryFetch { (fetchResult) in
            precondition(Thread.isMainThread)
            photoLibraryFetchResult = fetchResult
            dispatchGroup.leave()
        }

        var networkReloadResult: Result<Any?, Error> = .failure("not run")
        dispatchGroup.enter()
        fetchAndConsolidateCloudData { (result) in
            precondition(Thread.isMainThread)
            networkReloadResult = result
            dispatchGroup.leave()
        }

        dispatchGroup.notify(queue: .main) {
            self.consolidate(fetchResult: photoLibraryFetchResult) { [weak self] in
                // load asset manager queues (imports, deletes etc) only after (and if) cloud info has been refreshed
                if case .success(_) = networkReloadResult {
                    self?.assetManager.loadAndStartQueues()
                }
                self?.notifyObservers(reloadInProgress: false)
            }
        }
    }

    private func photoLibraryFetch(callback: @escaping (([PHAsset], [String])?) -> Void) {
        photoLibrary.requestAccess { [weak self] (success) in
            guard let self = self else {
                callback(nil)
                return
            }
            guard success else {
                callback(([PHAsset](), [String]()))
                return
            }
            self.photoLibrary.fetchAllAssets { (orderedAssets, localIDs) in
                callback((orderedAssets, localIDs))
            }
        }
    }

    private func consolidate(fetchResult: ([PHAsset], [String])?, callback: Closure? = nil) {
        guard let fetchResult = fetchResult else {
            callback?()
            return
        }
        modelController.consolidateWithIOSPhotoLibrary(orderedPHAssets: fetchResult.0, localIDsforPHAssets: fetchResult.1) {
            callback?()
        }
    }

    private func isLowOnCloudStorage(basedOn currentTier: StorageTier, callback: @escaping ClosureBool) {
        modelController.cloudStorageUsed { (usedStorage) in
            DispatchQueue.main.async {
                callback(usedStorage.totalSize >= currentTier.size)
            }
        }
    }
}

extension AppContext: AppContextObserverRegister {
    struct Status {
        let diskSpaceLow: Bool
        let cloudSpaceLow: Bool
        let networkDown: Bool
        let photoLibraryAccessDenied: Bool?
    }

    private struct AppContextObserverWrapper {
        weak var observer: AppContextObserver?
    }

    func addObserver(_ observer: AppContextObserver) {
        precondition(Thread.isMainThread)
        let id = ObjectIdentifier(observer)
        contextObservers[id] = AppContextObserverWrapper(observer: observer)
    }

    func removeObserver(_ observer: AppContextObserver) {
        precondition(Thread.isMainThread)
        let id = ObjectIdentifier(observer)
        contextObservers.removeValue(forKey: id)
    }

    func generateStatusNotification(lowDiskSpace: Bool? = nil, lowCloudSpace: Bool? = nil) {
        let dispatchGroup = DispatchGroup()

        var lowDiskSpace = lowDiskSpace
        if lowDiskSpace == nil {
            dispatchGroup.enter()
            self.lowDiskSpace { isLowOnDiskSpace in
                lowDiskSpace = isLowOnDiskSpace
                dispatchGroup.leave()
            }
        }

        var lowCloudSpace = lowCloudSpace
        if lowCloudSpace == nil {
            dispatchGroup.enter()
            self.lowCloudStorage { isLowOnCloudStorage in
                lowCloudSpace = isLowOnCloudStorage
                dispatchGroup.leave()
            }
        }

        let networkDown = !(networkMonitor?.isOnline ?? false)
        let photoLibraryAccessDenied = self.photoLibraryAccessDenied

        dispatchGroup.notify(queue: .main) {
            let status = Status(diskSpaceLow: lowDiskSpace!, cloudSpaceLow: lowCloudSpace!, networkDown: networkDown, photoLibraryAccessDenied: photoLibraryAccessDenied)
            for (id, observerWrapper) in self.contextObservers {
                guard let observer = observerWrapper.observer else {
                    self.contextObservers.removeValue(forKey: id)
                    continue
                }
                observer.handle(status: status)
            }
        }
    }

    private func notifyObservers(reloadInProgress: Bool) {
        DispatchQueue.main.async {
            for (id, observerWrapper) in self.contextObservers {
                guard let observer = observerWrapper.observer else {
                    self.contextObservers.removeValue(forKey: id)
                    continue
                }
                observer.reload(inProgress: reloadInProgress)
            }
        }
    }
}

extension AppContext: KeychainDelegate {
    var primaryUserKey: CryptoPrivateKey {
        return try! keychain.retrievePrivateKey(withFingerprint: primaryUser.fingerprint, keyType: .user)!
    }

    func groupKey(for groupID: UUID) -> CryptoPrivateKey? {
        guard let group = modelController.group(for: groupID) else { return nil }
        return try? keychain.retrievePrivateKey(withFingerprint: group.fingerprint, keyType: .group)
    }

    func assetKey(forFingerprint assetFingerprint: String) -> CryptoPrivateKey? {
        return try? keychain.retrievePrivateKey(withFingerprint: assetFingerprint, keyType: .asset)
    }

    func newAssetKey() -> CryptoPrivateKey {
        return keychain.generateNewPrivateKey(.asset, passwordProtected: false, saveToKeychain: true)
    }

    func delete(key: CryptoPrivateKey) throws {
        try keychain.deletePrivateKey(key)
    }

    func publicKey(type: KeyType, fingerprint: String) -> CryptoPublicKey? {
        return try? keychain.retrievePublicKey(withFingerprint: fingerprint, keyType: type)
    }

    func privateKey(type: KeyType, fingerprint: String) -> CryptoPrivateKey? {
        return try? keychain.retrievePrivateKey(withFingerprint: fingerprint, keyType: type)
    }

    func privateKey(from keyString: String, of keyType: KeyType) throws -> CryptoPrivateKey {
        do {
            return try keychain.createPrivateKey(for: keyType, from: keyString, password: nil, saveToKeychain: true)
        } catch KeychainError.duplicate(_) {
            return try keychain.createPrivateKey(for: keyType, from: keyString, password: nil, saveToKeychain: false)
        }
    }
}

extension AppContext: UserNotificationReceiver {
    func receive(_ notification: UserNotification, completion: @escaping ClosureBool) {
        switch (notification.type, notification.groupID) {
        case (.invitedToGroup, nil):
            modelController.refreshGroups(callback: completion)
        case (.userJoinedGroup, let .some(groupID)):
            guard let group = modelController.group(for: groupID) else {
                assertionFailure(groupID.string)
                completion(false)
                return
            }
            modelController.refreshUsers(for: group, callback: completion)
        case (.userLeftGroup, .some):
            modelController.refreshGroups { [weak self] success in
                guard success else {
                    completion(false)
                    return
                }
                self?.modelController.refreshAssets { [weak self] success in
                    guard success else {
                        completion(false)
                        return
                    }
                    self?.modelController.refreshGroupAlbums(callback: completion)
                }
            }
        case (.assetsChangedForGroup, .some), (.assetsAddedToGroupByUser, .some):
            modelController.refreshAssets { [weak self] success in
                guard success else {
                    completion(false)
                    return
                }
                self?.modelController.refreshGroupAlbums(callback: completion)
            }
        default:
            assertionFailure(String(describing: notification))
            completion(false)
        }
    }
}

extension AppContext: NetworkObserver {
    // Convergence point for context update requests
    func networkChanged(toState state: NetworkMonitor.State) {
        log.verbose("network changed to state: \(String(describing: state))")
        if UIApplication.shared.applicationState != .background {
            notifyObservers(reloadInProgress: true)
            if case .online(mobile: _) = state {
                fullContextUpdate()
            } else {
                photoLibraryFetch { [weak self] (fetchResult) in
                    self?.consolidate(fetchResult: fetchResult) {
                        self?.notifyObservers(reloadInProgress: false)
                    }
                }
            }
        }
        generateStatusNotification()
    }
}

extension AppContext: PurchasesObserver {
    func updated(storageTier: StorageTier) {
        isLowOnCloudStorage(basedOn: storageTier) { [weak self] (lowCloudSpace) in
            self?.generateStatusNotification(lowCloudSpace: lowCloudSpace)
        }
    }
}

extension AppContext: UserObserver {
    func updated(_ user: User) {
        guard user.uuid == primaryUser.uuid else { return }
        primaryUser = user
    }
}
