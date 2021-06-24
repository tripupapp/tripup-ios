//
//  AssetManager.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 22/04/2020.
//  Copyright © 2020 Vinoth Ramiah. All rights reserved.
//

import Foundation
import Photos
import UIKit.UIApplication

protocol MutableAssetProtocol: AnyObject {
    var uuid: UUID { get }
}

protocol MutableAssetDatabase: AnyObject {
    func fingerprint(for asset: AssetManager.MutableAsset) -> String?
    func save(fingerprint: String, for asset: AssetManager.MutableAsset)
    func uti(for asset: AssetManager.MutableAsset) -> String?
    func save(uti: String, for asset: AssetManager.MutableAsset)
    func localIdentifier(for asset: AssetManager.MutableAsset) -> String?
    func save(localIdentifier: String?, for asset: AssetManager.MutableAsset)
    func md5(for asset: AssetManager.MutableAsset) -> Data?
    func save(md5: Data, for asset: AssetManager.MutableAsset)
    func cloudFilesize(for asset: AssetManager.MutableAsset) -> UInt64
    func save(cloudFilesize: UInt64, for asset: AssetManager.MutableAsset)
    func importStatus(for asset: AssetManager.MutableAsset) -> Bool
    func save(importStatus: Bool, for asset: AssetManager.MutableAsset)
    func deleteStatus(for asset: AssetManager.MutableAsset) -> Bool
    func save(deleteStatus: Bool, for asset: AssetManager.MutableAsset)
    func remotePath(for asset: AssetManager.MutablePhysicalAsset) -> URL?
    func save(remotePath: URL?, for asset: AssetManager.MutablePhysicalAsset)
}

protocol AssetImportManager: AnyObject {
    func priorityImport<T>(_ assets: T, callback: @escaping ClosureBool) where T: Collection, T.Element == Asset
}

protocol AssetShareManager: AnyObject {
    func encryptAssetKeys(withKey encryptionKey: CryptoPublicKey, forAssetsWithIDs assetIDs: [UUID], callback: @escaping (Bool, [String]) -> Void)
}

protocol AssetSyncManager: AnyObject {
    func removeDeletedAssets<T>(ids deletedAssetIDs: T) where T: Collection, T.Element == UUID
    func removeInvalidAssets<T>(ids invalidAssetIDs: T) where T: Collection, T.Element == UUID
}

class AssetManager {
    enum Quality: String {
        case original
        case low
    }

    enum ImageRequestFormat {
        case best
        case highQuality(CGSize, CGFloat)
        case lowQuality(CGSize, CGFloat)
        case fast
    }

    enum AVRequestFormat {
        case best
        case opportunistic
        case fast
    }

    struct ResultInfo {
        let final: Bool
        let uti: AVFileType?
    }

    unowned let keychainDelegate: KeychainDelegate
    unowned let assetController: AssetController

    let photoLibrary: PhotoLibrary
    let iosImageManager = PHImageManager.default()
    let dataService: DataService
    let webAPI: API
    let syncTracker = AssetSyncTracker()

    let log = Logger.self
    let assetManagerQueue = DispatchQueue(label: String(describing: AssetManager.self), qos: .default, target: .global())
    let keychainQueue = DispatchQueue(label: String(describing: AssetManager.self) + ".Keychain", qos: .utility, target: DispatchQueue.global())
    var triggerStatusNotification: Closure?

    private unowned let assetDatabase: MutableAssetDatabase
    private weak var networkController: NetworkMonitorController?

    private let liveAssets = Cache<UUID, MutableAsset>()    // used as database cache but also to ensure multiple operations refer to the same asset instance for data consistency
    private var autoQueuer: AssetImportQueuingOperation?
    private var manualQueuer: AssetManualImportQueuingOperation?
    private let importQueue = OperationQueue()
    private let downloadQueue = OperationQueue()
    private let deleteQueue = OperationQueue()
    /** [assetid: [operationid: operation]] */
    private var assetOperations = [UUID: [UUID: Operation]]()
    /** [assetid: [operationname: [callback]] */
    private var callbacksForAssetOperations = [UUID: [String: [ClosureBool]]]()

    private var autoBackupObserverToken: NSObjectProtocol?
    private var resignActiveObserverToken: NSObjectProtocol?
    private var didBecomeActiveObserverToken: NSObjectProtocol?
    private var enterBackgroundObserverToken: NSObjectProtocol?

    init(assetController: AssetController, assetDatabase: MutableAssetDatabase, photoLibrary: PhotoLibrary, keychainDelegate: KeychainDelegate, apiUser: APIUser, webAPI: API, dataService: DataService, networkController: NetworkMonitorController?) {
        self.assetController = assetController
        self.assetDatabase = assetDatabase
        self.photoLibrary = photoLibrary
        self.keychainDelegate = keychainDelegate
        self.dataService = dataService
        self.networkController = networkController
        self.webAPI = webAPI

        importQueue.qualityOfService = .utility
        downloadQueue.qualityOfService = .userInitiated
        deleteQueue.qualityOfService = .default

        let cacheDelegate = CacheDelegateAssetManager()
        cacheDelegate.assetManager = self
        liveAssets.delegate = cacheDelegate

        autoBackupObserverToken = NotificationCenter.default.addObserver(forName: .AutoBackupChanged, object: nil, queue: nil) { [unowned self] notification in
            guard let autoBackup = notification.object as? Bool else {
                self.log.error("unrecognised object sent by notification - notification: \(notification.name), object: \(String(describing: notification.object))")
                assertionFailure()
                return
            }
            self.log.verbose("received notification - name: \(notification.name), value: \(autoBackup)")
            if autoBackup {
                self.autoQueueUnimportedAssetIDs()
            } else {
                self.assetManagerQueue.async { [weak self] in
                    if let pendingItems = self?.autoQueuer?.assetImportList.value, pendingItems.isNotEmpty {
                        self?.syncTracker.removeTracking(pendingItems)
                    }
                    self?.autoQueuer?.cancel()
                    self?.importQueue.cancelAllOperations()
                    self?.importQueue.isSuspended = false
                }
            }
        }

        resignActiveObserverToken = NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: nil) { [unowned self] (_) in
            self.log.verbose("received notification - name: \(UIApplication.willResignActiveNotification)")
            self.assetManagerQueue.async { [weak self] in
                self?.suspendImportOperations(true)
                self?.importQueue.isSuspended = true
                self?.deleteQueue.isSuspended = true
                self?.downloadQueue.isSuspended = true
            }
        }

        didBecomeActiveObserverToken = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: nil) { [unowned self] (_) in
            self.log.verbose("received notification - name: \(UIApplication.didBecomeActiveNotification)")
            self.assetManagerQueue.async { [weak self] in
                self?.downloadQueue.isSuspended = false // always keep download queue unsuspended whenever possible
            }
        }

        enterBackgroundObserverToken = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil) { [unowned self] (_) in
            self.log.verbose("received notification - name: \(UIApplication.didEnterBackgroundNotification)")
            self.assetManagerQueue.async { [weak self] in
                if let pendingItems = self?.assetOperations.keys, pendingItems.isNotEmpty {
                    self?.syncTracker.removeTracking(pendingItems)
                }
                self?.autoQueuer?.cancel()
                self?.importQueue.cancelAllOperations()
                self?.downloadQueue.cancelAllOperations()
                self?.deleteQueue.cancelAllOperations()
                // must resume queues in order to process cancellation events
                self?.importQueue.isSuspended = false
                self?.deleteQueue.isSuspended = false
            }
        }
    }

    deinit {
        if let autoBackupObserverToken = autoBackupObserverToken {
            NotificationCenter.default.removeObserver(autoBackupObserverToken, name: .AutoBackupChanged, object: nil)
        }
        if let resignActiveObserverToken = resignActiveObserverToken {
            NotificationCenter.default.removeObserver(resignActiveObserverToken, name: UIApplication.willResignActiveNotification, object: nil)
        }
        if let didBecomeActiveObserverToken = didBecomeActiveObserverToken {
            NotificationCenter.default.removeObserver(didBecomeActiveObserverToken, name: UIApplication.didBecomeActiveNotification, object: nil)
        }
        if let enterBackgroundObserverToken = enterBackgroundObserverToken {
            NotificationCenter.default.removeObserver(enterBackgroundObserverToken, name: UIApplication.didEnterBackgroundNotification, object: nil)
        }
    }
}

// MARK: public functions for app functionality
extension AssetManager {
    func loadAndStartQueues() {
        if UserDefaults.standard.bool(forKey: UserDefaultsKey.AutoBackup.rawValue) {
            autoQueueUnimportedAssetIDs()
        }
        assetController.deletedAssetIDs { [weak self] (deletedAssetIDs) in
            guard let deletedAssetIDs = deletedAssetIDs, deletedAssetIDs.isNotEmpty else {
                return
            }
            self?.syncTracker.startTracking(deletedAssetIDs)
            self?.mutableAssets(from: deletedAssetIDs) { (mutableAssets) in
                self?.queueNewDeleteOperation(for: mutableAssets)
            }
        }
    }

    func startBackgroundImports(callback: @escaping ClosureBool) {
        if importQueue.isSuspended {
            log.debug("import queue is suspended. refreshing network state in an attempt to turn back on")
            networkController?.refresh()
        }
        retrieveUnimportedAssetIDs { [weak self] (unimportedAssetIDs) in
            guard let self = self else {
                callback(false)
                return
            }
            let assetIDs: [UUID] = unimportedAssetIDs.suffix(100)
            self.mutableAssets(from: assetIDs) { [weak self] (unimportedAssets) in
                guard let self = self else {
                    callback(false)
                    return
                }
                guard unimportedAssets.isNotEmpty else {
                    callback(true)
                    return
                }
                let operation = AssetImportOperation(assets: unimportedAssets, delegate: self)
                operation.completionBlock = { [weak self, weak operation] in
                    guard let self = self, let operation = operation else {
                        callback(false)
                        return
                    }
                    self.assetManagerQueue.sync { [weak self] in
                        self?.clear(operation: operation)
                    }
                    switch operation.currentState {
                    case .some(is AssetImportOperation.Success):
                        callback(true)
                    case .some(is AssetImportOperation.Fatal):
                        self.terminate(assets: unimportedAssets)
                        callback(true)
                    default:
                        callback(false)
                    }
                }
                self.queue(operation: operation)
            }
        }
    }

    func cancelBackgroundImports() {
        importQueue.cancelAllOperations()
        importQueue.isSuspended = false
    }
}

// MARK: functions called directly by UI
extension AssetManager {
    func delete<T>(_ assets: T) where T: Collection, T.Element == Asset {
        assert(assets.isNotEmpty)
        mutableAssets(from: assets.map{ $0.uuid }) { [weak self] mutableAssets in
            guard let self = self else {
                return
            }
            assert(mutableAssets.count == assets.count)
            var trackingIDs = [UUID]()
            var localIDs = [String]()
            var assetsOnClientOnly = [MutableAsset]()
            var assetsOnServer = [MutableAsset]()
            for asset in mutableAssets {
                if asset.imported || self.operationScheduledOrInProgressOfType(AssetImportOperation.self, forAsset: asset) {
                    assetsOnServer.append(asset)
                    asset.deleted = true
                    trackingIDs.append(asset.uuid)
                } else {
                    assetsOnClientOnly.append(asset)
                }
                if let localIdentifier = asset.localIdentifier {
                    localIDs.append(localIdentifier)
                }
            }
            if trackingIDs.isNotEmpty {
                self.syncTracker.startTracking(trackingIDs)
            }
            if assetsOnServer.isNotEmpty {
                self.queueNewDeleteOperation(for: assetsOnServer)
            }
            if assetsOnClientOnly.isNotEmpty {
                self.terminate(assets: assetsOnClientOnly)
            }
            if localIDs.isNotEmpty {
                self.photoLibrary.fetchAssets(withLocalIdentifiers: localIDs) { iosAssets in
                    let iosAssets = iosAssets.compactMap{ $0 }
                    guard iosAssets.isNotEmpty else { return }
                    PHPhotoLibrary.shared().performChanges({
                        PHAssetChangeRequest.deleteAssets(iosAssets as NSArray)
                    })  // completionHandler triggers error when denying deletion only on iOS 12
                }
            }
        }
    }

    func saveToIOS(asset: Asset, callback: @escaping (_ success: Bool, _ wasAlreadySaved: Bool) -> Void) {
        let callbackOnMain = { (_ success: Bool, _ wasAlreadySaved: Bool) -> Void in
            DispatchQueue.main.async {
                callback(success, wasAlreadySaved)
            }
        }
        guard asset.imported else {
            callbackOnMain(false, true)
            return
        }
        let phAssetResourceType: PHAssetResourceType
        switch asset.type {
        case .photo:
            phAssetResourceType = .photo
        case .video:
            phAssetResourceType = .video
        case .audio, .unknown:
            assertionFailure()
            callbackOnMain(false, false)
            return
        }
        assetController.localIdentifier(forAsset: asset) { [weak self] (existinglocalIdentifier) in
            guard existinglocalIdentifier == nil else {
                callbackOnMain(false, true)
                return
            }
            self?.load(asset: asset, atQuality: .original) { (url, uti) in
                guard let url = url else {
                    callbackOnMain(false, false)
                    return
                }
                var newAssetPlaceholder: PHObjectPlaceholder?
                PHPhotoLibrary.shared().performChanges({
                    let options = PHAssetResourceCreationOptions()
                    options.uniformTypeIdentifier = uti?.rawValue
                    let newAsset = PHAssetCreationRequest.forAsset()
                    newAssetPlaceholder = newAsset.placeholderForCreatedAsset
                    newAsset.addResource(with: phAssetResourceType, fileURL: url, options: options)
                    newAsset.creationDate = asset.creationDate
                    newAsset.location = asset.location?.coreLocation
                    newAsset.isFavorite = asset.favourite
                }) { (successfullySavedToLibrary, _) in
                    guard successfullySavedToLibrary, let localIdentifier = newAssetPlaceholder?.localIdentifier else {
                        callbackOnMain(false, false)
                        return
                    }
                    // write localIdentifier to local database
                    self?.mutableAsset(from: asset.uuid) { (mutableAsset) in
                        if let mutableAsset = mutableAsset {
                            mutableAsset.localIdentifier = localIdentifier
                        }
                        callbackOnMain(true, false)
                    }
                }
            }
        }
    }
}

// MARK: AssetManager internal functions
extension AssetManager {
    func loadData(for asset: Asset, atQuality quality: Quality, callback: @escaping (Data?, AVFileType?) -> Void) {
        precondition(asset.type == .photo)
        mutableAsset(from: asset.uuid) { [weak self] mutableAsset in     // load mutable asset from live asset cache or database
            guard let self = self, let mutableAsset = mutableAsset else { DispatchQueue.main.async { callback(nil, nil) }; return }
            precondition(.on(self.assetManagerQueue))
            self.loadData(for: mutableAsset, atQuality: quality, callback: callback)
        }
    }

    func generateStillImage(forAsset asset: Asset, maxSize: CGSize = .zero, callback: @escaping (UIImage?, AVFileType?) -> Void) {
        precondition(asset.type == .video)
        load(asset: asset, atQuality: .low) { [weak self] (url, uti) in
            guard let url = url else {
                self?.log.error("\(asset.uuid): unable to fetch resource - quality: low")
                callback(nil, uti)
                return
            }
            let avAsset = AVAsset(url: url)
            let avAssetImageGenerator = AVAssetImageGenerator(asset: avAsset)
            avAssetImageGenerator.appliesPreferredTrackTransform = true
            avAssetImageGenerator.maximumSize = maxSize
            avAssetImageGenerator.generateCGImagesAsynchronously(forTimes: [NSValue(time: .zero)]) { (_, cgImage, _, _, error) in
                if let cgImage = cgImage {
                    callback(UIImage(cgImage: cgImage), AVFileType(cgImage.utType as String?))
                } else {
                    self?.log.error(String(describing: error))
                    callback(nil, nil)
                }
            }
        }
    }

    func load(asset: Asset, atQuality quality: Quality, callback: @escaping (URL?, AVFileType?) -> Void) {
        mutableAsset(from: asset.uuid) { [weak self] (mutableAsset) in
            guard let self = self else {
                callback(nil, nil)
                return
            }
            guard let mutableAsset = mutableAsset else {
                self.log.verbose("\(asset.uuid): mutableAsset not found")
                callback(nil, nil)
                return
            }
            self.fetchResource(forPhysicalAsset: mutableAsset.physicalAssets[quality]) { [weak self] (success) in
                if success {
                    callback(mutableAsset.physicalAssets[quality].localPath, mutableAsset.originalUTI)
                } else {
                    self?.log.verbose("\(asset.uuid): failed to fetch resource - quality: \(String(describing: quality))")
                    callback(nil, nil)
                }
            }
        }
    }

    func mutableAssets<T>(from assetIDs: T, callback: @escaping ([MutableAsset]) -> Void) where T: Collection, T.Element == UUID {
        loadMutableAssets(from: assetIDs) { [weak self] (mutableAssets) in
            precondition(.on(self?.assetManagerQueue))
            callback(mutableAssets)
        }
    }
}

// MARK: AssetManager specific functions
private extension AssetManager {
    private func retrieveUnimportedAssetIDs(callback: @escaping ([UUID]) -> Void) {
        assetController.allAssets { (allAssets) in
            let unimportedAssetIDs = allAssets.values.sorted(by: .creationDate(ascending: true)).compactMap{ $0.imported ? nil : $0.uuid }
            DispatchQueue.global().async {
                callback(unimportedAssetIDs)
            }
        }
    }

    private func mutableAsset(from assetID: UUID, callback: @escaping (MutableAsset?) -> Void) {
        mutableAssets(from: [assetID]) { [weak self] mutableAssets in
            guard let self = self else { return }
            precondition(.on(self.assetManagerQueue))
            callback(mutableAssets.first)
        }
    }

    private func loadData(for mutableAsset: MutableAsset, atQuality quality: Quality, callback: @escaping (Data?, AVFileType?) -> Void) {
        let mutablePhysicalAsset = mutableAsset.physicalAssets[quality]
        self.loadData(from: mutablePhysicalAsset.localPath) { [weak self] data in    // try to load from disk
            guard let self = self else {
                DispatchQueue.main.async {
                    callback(nil, nil)
                }
                return
            }
            precondition(.on(self.assetManagerQueue))

            let originalUTI = mutableAsset.originalUTI
            if let data = data {
                DispatchQueue.main.async {
                    callback(data, originalUTI)
                }
            } else {
                guard !self.downloadQueue.isSuspended else {
                    DispatchQueue.main.async {
                        callback(nil, originalUTI)
                    }
                    return
                }
                // not found on disk, so schedule request for later and create a download operation
                let downloadRequest = { [weak self] (success: Bool) in
                    guard let self = self else {
                        DispatchQueue.main.async {
                            callback(nil, originalUTI)
                        }
                        return
                    }
                    self.loadData(from: mutablePhysicalAsset.localPath) { data in
                        DispatchQueue.main.async {
                            callback(data, originalUTI)
                        }
                    }
                }
                self.schedule(callback: downloadRequest, for: AssetDownloadOperation.lookupKey, onAssetID: mutablePhysicalAsset.uuid)
                self.queueNewDownloadOperation(for: [mutablePhysicalAsset])
            }
        }
    }

    private func loadData(from url: URL, callback: @escaping (Data?) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let data = self.load(url)
            self.assetManagerQueue.async {
                callback(data)
            }
        }
    }

    private func fetchResource(forPhysicalAsset physicalAsset: MutablePhysicalAsset, callback: @escaping (Bool) -> Void) {
        if let isReachable = try? physicalAsset.localPath.checkResourceIsReachable(), isReachable {
            callback(true)
        } else {
            // not found on disk, so schedule request for later and create a download operation
            guard !downloadQueue.isSuspended else {
                callback(false)
                return
            }
            schedule(callback: callback, for: AssetDownloadOperation.lookupKey, onAssetID: physicalAsset.uuid)
            queueNewDownloadOperation(for: [physicalAsset])
        }
    }

    private func removeDeletedAssets<T: Collection>(_ deletedAssets: T) where T.Element == MutableAsset {
        precondition(.on(assetManagerQueue))
        syncTracker.startTracking(deletedAssets.map{ $0.uuid })
        queueNewDeleteOperation(for: Array(deletedAssets), state: .deletedFromServer)
    }

    private func terminate<T>(assets: T) where T: Collection, T.Element == MutableAsset {
        let assetIDs = assets.map{ $0.uuid }
        log.debug("terminating assets with ids: \(assetIDs.map{ $0.string })")
        let fingerprints = assets.compactMap{ $0.fingerprint }
        keychainQueue.async { [weak self] in
            for fingerprint in fingerprints {
                if let key = self?.keychainDelegate.assetKey(forFingerprint: fingerprint) {
                    try? self?.keychainDelegate.delete(key: key)
                }
            }
        }
        liveAssets.removeObjects(forKeys: assetIDs)
        assetController.remove(assets: assets)
    }
}

// MARK: AssetManager caching functions
private extension AssetManager {
    private class CacheDelegateAssetManager: CacheDelegate<UUID> {
        weak var assetManager: AssetManager?

        override func isDiscardable<T>(keysToTest: T, callbackWithDiscardableKeys: @escaping (AnyCollection<UUID>) -> Void) where T: Collection, T.Element == UUID {
            if let assetManager = assetManager {
                assetManager.isDiscardable(keysToTest: keysToTest, callbackWithDiscardableKeys: callbackWithDiscardableKeys)
            } else {
                callbackWithDiscardableKeys(AnyCollection(keysToTest))
            }
        }
    }

    private func isDiscardable<T>(keysToTest: T, callbackWithDiscardableKeys: @escaping (AnyCollection<UUID>) -> Void) where T: Collection, T.Element == UUID {
        assetManagerQueue.async { [weak self] in
            if let self = self {
                let discarcableKeys = keysToTest.filter{ !self.operationsExist(forAssetID: $0) }
                callbackWithDiscardableKeys(AnyCollection(discarcableKeys))
            } else {
                callbackWithDiscardableKeys(AnyCollection(keysToTest))
            }
        }
    }

    private func loadMutableAssets<T>(from assetIDs: T, callback: @escaping ([MutableAsset]) -> Void) where T: Collection, T.Element == UUID {
        DispatchQueue.global().async {
            var cachedAssets = [MutableAsset]()
            var assetIDsToRetrieveFromDB = [UUID]()
            for id in assetIDs {
                if let asset = self.liveAssets.object(forKey: id) {
                    cachedAssets.append(asset)
                } else {
                    assetIDsToRetrieveFromDB.append(id)
                }
            }
            guard assetIDsToRetrieveFromDB.isNotEmpty else {
                self.assetManagerQueue.async {
                    callback(cachedAssets)
                }
                return
            }

            self.assetController.mutableAssets(for: assetIDsToRetrieveFromDB) { [weak self] (result) in
                guard let self = self else {
                    return
                }
                do {
                    let result = try result.get()
                    for asset in result.0 {
                        do {
                            try self.liveAssets.setObject(asset, forKey: asset.uuid)
                            asset.database = self.assetDatabase
                            cachedAssets.append(asset)
                        } catch Cache<UUID, MutableAsset>.CacheError.objectExistsForKey(_, let existingAsset) {
                            cachedAssets.append(existingAsset)
                        }
                    }
                    if result.1.isNotEmpty {
                        self.syncTracker.removeTracking(result.1)
                    }
                } catch {
                    self.log.error(String(describing: error))
                    assertionFailure()
                }
                self.assetManagerQueue.async {
                    callback(cachedAssets)
                }
            }
        }
    }
}

// MARK: operation and queing functions
private extension AssetManager {
    private func autoQueueUnimportedAssetIDs() {
        retrieveUnimportedAssetIDs { [weak self] (unimportedAssetIDs) in
            guard unimportedAssetIDs.isNotEmpty else {
                return
            }
            self?.assetManagerQueue.async { [weak self] in
                self?.autoQueue(assetIDs: unimportedAssetIDs)
            }
        }
    }

    private func autoQueue(assetIDs: [UUID]) {
        precondition(.on(assetManagerQueue))
        var assetIDs = assetIDs
        if let autoQueuer = autoQueuer, !autoQueuer.isFinished {
            autoQueuer.assetImportList.mutate { queuedIDs in
                let queuedIDsSet = Set(queuedIDs)
                assetIDs.removeAll(where: { queuedIDsSet.contains($0) })
                queuedIDs.append(contentsOf: assetIDs)
            }
        } else {
            let autoQueuer = AssetImportQueuingOperation(assetImportList: assetIDs, operationDelegate: self)
            autoQueuer.delegate = self
            autoQueuer.conditions = {
                return UserDefaults.standard.bool(forKey: UserDefaultsKey.AutoBackup.rawValue)
            }
            autoQueuer.completionBlock = { [weak self] in
                self?.assetManagerQueue.async { [weak self] in
                    guard let self = self else {
                        return
                    }
                    if self.autoQueuer === autoQueuer {
                        self.autoQueuer = nil
                    }
                }
            }
            self.autoQueuer = autoQueuer
            DispatchQueue.global().async {
                self.autoQueuer?.start()
            }
        }
        if assetIDs.isNotEmpty {
            syncTracker.startTracking(assetIDs)
        }
    }

    private func manualQueue(assetIDs: [UUID]) {
        precondition(.on(assetManagerQueue))
        if let manualQueuer = manualQueuer, !manualQueuer.isFinished {
            manualQueuer.assetImportList.mutate{ $0.append(contentsOf: assetIDs) }
        } else {
            let manualQueuer = AssetManualImportQueuingOperation(assetImportList: assetIDs, operationDelegate: self)
            manualQueuer.delegate = self
            manualQueuer.completionBlock = { [weak self] in
                self?.assetManagerQueue.async { [weak self] in
                    guard let self = self else {
                        return
                    }
                    if self.manualQueuer === manualQueuer {
                        self.manualQueuer = nil
                    }
                }
            }
            self.manualQueuer = manualQueuer
            DispatchQueue.global().async {
                self.manualQueuer?.start()
            }
        }
    }

    private func queue<T>(operation: AssetOperationBatch<T>) where T: MutableAssetProtocol {
        precondition(.on(assetManagerQueue))
        for asset in operation.assets {
            if (assetOperations[asset.uuid]?[operation.id] = operation) == nil {
                assetOperations[asset.uuid] = [operation.id: operation]
            }
        }

        switch operation {
        case is AssetImportOperation:
            importQueue.addOperation(operation)
        case is AssetDownloadOperation:
            downloadQueue.addOperation(operation)
        case is AssetDeleteOperation:
            deleteQueue.addOperation(operation)
        default:
            assertionFailure(String(describing: operation))
        }
    }

    private func clear<T>(operation: AssetOperationBatch<T>) where T: MutableAssetProtocol {
        precondition(.on(assetManagerQueue))
        var completedIDs = [UUID]()
        for asset in operation.assets {
            assetOperations[asset.uuid]?[operation.id] = nil
            if assetOperations[asset.uuid]?.isEmpty ?? true {
                completedIDs.append(asset.uuid)
            }
        }
        if completedIDs.isNotEmpty {
            syncTracker.completeTracking(completedIDs)
        }
    }

    private func clear(deleteOperation operation: AssetDeleteOperation) {
        assetManagerQueue.async { [weak self] in
            self?.clear(operation: operation)
        }
    }

    private func suspendImportOperations(_ value: Bool) {
        precondition(.on(assetManagerQueue))
        for operations in assetOperations.values {
            for (_, operation) in operations {
                if let operation = operation as? AssetImportOperation {
                    operation.suspend(value)
                }
            }
        }
    }

    private func handleOperationQueues(status: AppContext.Status) {
        importQueue.isSuspended = status.diskSpaceLow || status.cloudSpaceLow || status.networkDown
        deleteQueue.isSuspended = status.networkDown
        if status.diskSpaceLow || status.networkDown {
            downloadQueue.cancelAllOperations()
        }
    }

    private func findScheduledOperationOfType<T, U>(_ type: T.Type, forAsset asset: U, includeInProgress: Bool = false) -> T? where T: AssetOperationBatch<U>, U: MutableAssetProtocol {
        precondition(.on(assetManagerQueue))
        let operationTypeIsScheduled: (Operation) -> Bool = { (operation: Operation) in
            guard let operation = operation as? T else {
                return false
            }
            if includeInProgress {
                return !operation.isFinished
            } else {
                return !operation.isExecuting && !operation.isFinished
            }
        }
        if let operation = assetOperations[asset.uuid]?.values.first(where: operationTypeIsScheduled) as? T {
            return operation
        }
        return nil
    }

    private func findScheduledOrInProgressOperationOfType<T, U>(_ type: T.Type, forAsset asset: U) -> T? where T: AssetOperationBatch<U>, U: MutableAssetProtocol {
        return findScheduledOperationOfType(type, forAsset: asset, includeInProgress: true)
    }

    private func operationScheduledOrInProgressOfType<T, U>(_ type: T.Type, forAsset asset: U) -> Bool where T: AssetOperationBatch<U>, U: MutableAssetProtocol {
        precondition(.on(assetManagerQueue))
        return findScheduledOrInProgressOperationOfType(type, forAsset: asset) != nil
    }

    private func operationsExist(forAssetID assetID: UUID) -> Bool {
        precondition(.on(assetManagerQueue))
        return assetOperations[assetID]?.isNotEmpty ?? false
    }

    private func schedule(callback: @escaping ClosureBool, for operationLookupKey: String, onAssetID assetID: UUID) {
        precondition(.on(assetManagerQueue))
        if var operationCallbacks = callbacksForAssetOperations[assetID] {
            if var callbacks = operationCallbacks[operationLookupKey] {
                callbacks.append(callback)
                callbacksForAssetOperations[assetID]![operationLookupKey] = callbacks
            } else {
                operationCallbacks[operationLookupKey] = [callback]
                callbacksForAssetOperations[assetID] = operationCallbacks
            }
        } else {
            callbacksForAssetOperations[assetID] = [operationLookupKey: [callback]]
        }
    }

    private func runCallbacks<T>(for operation: AssetOperationBatch<T>, success: Bool) where T: MutableAssetProtocol {
        precondition(.on(assetManagerQueue))
        for asset in operation.assets {
            if let callbacks = callbacksForAssetOperations[asset.uuid]?[type(of: operation).lookupKey] {
                callbacks.forEach{ $0(success) }
                callbacksForAssetOperations[asset.uuid]?[type(of: operation).lookupKey] = nil
            }
        }
    }

    private func queueNewDownloadOperation(for assets: [MutablePhysicalAsset]) {
        precondition(.on(assetManagerQueue))
        let assets = assets.filter{ !operationScheduledOrInProgressOfType(AssetDownloadOperation.self, forAsset: $0) }
        guard assets.isNotEmpty else {
            return
        }
        let operation = AssetDownloadOperation(assets: assets, delegate: self)
        operation.completionBlock = { [weak self, weak operation] in
            self?.assetManagerQueue.async { [weak self, weak operation] in
                guard let self = self, let operation = operation else {
                    return
                }
                var success = false
                if case .success(_) = operation.result {
                    success = true
                }
                self.runCallbacks(for: operation, success: success)
                self.clear(operation: operation)
            }
        }
        queue(operation: operation)
    }

    private func queueNewDeleteOperation(for assets: [MutableAsset], state: AssetDeleteOperation.State? = nil) {
        precondition(.on(assetManagerQueue))
        let assets = assets.filter{ !operationScheduledOrInProgressOfType(AssetDeleteOperation.self, forAsset: $0) }
        guard assets.isNotEmpty else {
            return
        }
        let deleteOperation = AssetDeleteOperation(assets: assets, delegate: self, currentState: state)
        for asset in assets {
            if let importOperation = findScheduledOperationOfType(AssetImportOperation.self, forAsset: asset) {
                deleteOperation.addDependency(importOperation)
            }
            if let downloadOperation = findScheduledOperationOfType(AssetDownloadOperation.self, forAsset: asset.physicalAssets.low) {
                deleteOperation.addDependency(downloadOperation)
            }
            if let downloadOperation = findScheduledOperationOfType(AssetDownloadOperation.self, forAsset: asset.physicalAssets.original) {
                deleteOperation.addDependency(downloadOperation)
            }
        }
        deleteOperation.completionBlock = { [weak self, weak deleteOperation] in
            guard let self = self, let operation = deleteOperation else {
                return
            }
            switch operation.currentState.value {
            case .some(.deletedFromDisk):
                self.terminate(assets: assets)
            case .some(.deletedFromServer):
                self.deleteQueue.isSuspended = true
                self.queueNewDeleteOperation(for: assets, state: .deletedFromServer)
                self.checkSystemFull()
            case .none:
                self.deleteQueue.isSuspended = true
                self.queueNewDeleteOperation(for: assets)
                self.checkSystemFull()
            }
            self.clear(deleteOperation: operation)
        }
        queue(operation: deleteOperation)
    }
}

extension AssetManager: AssetImportOperationDelegate {
    func filterImported(assets: [MutableAsset]) -> [MutableAsset] {
        precondition(.on(assetManagerQueue))
        return assets.filter{ !$0.imported && !operationScheduledOrInProgressOfType(AssetImportOperation.self, forAsset: $0) }
    }

    func queue(importOperation operation: AssetImportOperation) {
        assetManagerQueue.async { [weak self] in
            self?.queue(operation: operation)
        }
    }

    func clear(importOperation operation: AssetImportOperation) {
        assetManagerQueue.async { [weak self] in
            self?.clear(operation: operation)
        }
    }

    func completed(importOperation operation: AssetImportOperation, success: Bool, terminate: Bool) {
        assetManagerQueue.async { [weak self] in
            self?.runCallbacks(for: operation, success: success)
            if terminate {
                self?.terminate(assets: operation.assets)
            }
        }
    }

    func suspendImports() {
        importQueue.isSuspended = true
    }

    func checkSystem() {
        triggerStatusNotification?()
    }

    func checkSystemFull() {
        networkController?.refresh()
    }
}

extension AssetManager: AssetImportManager {
    func priorityImport<T>(_ assets: T, callback: @escaping ClosureBool) where T: Collection, T.Element == Asset {
        let unimportedAssetIDs = assets.filter{ !$0.imported }.map{ $0.uuid }
        guard unimportedAssetIDs.isNotEmpty else {
            callback(true)
            return
        }
        assetManagerQueue.async { [weak self] in
            guard let self = self else {
                DispatchQueue.global().async {
                    callback(false)
                }
                return
            }
            let dispatchGroup = DispatchGroup()
            var allSuccess = true
            let importRequest: ClosureBool = { [weak self] success in
                assert(.on(self?.assetManagerQueue))
                allSuccess = allSuccess && success
                dispatchGroup.leave()
            }

            for assetID in unimportedAssetIDs {
                dispatchGroup.enter()
                self.schedule(callback: importRequest, for: AssetImportOperation.lookupKey, onAssetID: assetID)
            }
            self.syncTracker.startTracking(unimportedAssetIDs)
            self.manualQueue(assetIDs: unimportedAssetIDs)

            dispatchGroup.notify(queue: .global()) {
                callback(allSuccess)
            }
        }
    }
}

extension AssetManager: AssetShareManager {
    func encryptAssetKeys(withKey encryptionKey: CryptoPublicKey, forAssetsWithIDs assetIDs: [UUID], callback: @escaping (Bool, [String]) -> Void) {
        mutableAssets(from: assetIDs) { [weak self] mutableAssets in
            let fingerprints = mutableAssets.compactMap{ $0.fingerprint }
            self?.keychainQueue.async { [weak self] in
                let assetKeys = fingerprints.compactMap{ self?.keychainDelegate.assetKey(forFingerprint: $0) }
                let primaryUserKey = self?.keychainDelegate.primaryUserKey
                DispatchQueue.global().async {
                    let encryptedAssetKeys = assetKeys.map{ encryptionKey.encrypt($0.private, signed: primaryUserKey) }
                    DispatchQueue.main.async {
                        callback(encryptedAssetKeys.count == assetIDs.count, encryptedAssetKeys)
                    }
                }
            }
        }
    }
}

extension AssetManager: AssetSyncManager {
    func removeDeletedAssets<T>(ids deletedAssetIDs: T) where T: Collection, T.Element == UUID {
        mutableAssets(from: deletedAssetIDs) { [weak self] (removedMutableAssets) in
            if removedMutableAssets.isNotEmpty {
                self?.removeDeletedAssets(removedMutableAssets)
            }
        }
    }

    func removeInvalidAssets<T>(ids invalidAssetIDs: T) where T: Collection, T.Element == UUID {
        syncTracker.removeTracking(invalidAssetIDs)
        mutableAssets(from: invalidAssetIDs) { [weak self] (invalidMutableAssets) in
            if invalidMutableAssets.isNotEmpty {
                self?.terminate(assets: invalidMutableAssets)
            }
        }
    }
}

extension AssetManager: AppContextObserver {
    func handle(status: AppContext.Status) {
        assetManagerQueue.async { [weak self] in
            self?.log.debug(String(describing: status))
            self?.suspendImportOperations(status.diskSpaceLow || status.cloudSpaceLow || status.networkDown)
            self?.handleOperationQueues(status: status)
        }
    }
}
