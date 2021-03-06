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
    func filename(for asset: AssetManager.MutableAsset) -> String?
    func save(filename: String, for asset: AssetManager.MutableAsset)
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

protocol AssetManagerOperation: Operation {
    var id: UUID { get }
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

    enum OperationError: Error {
        case cancelled
    }

    struct ResultInfo {
        let final: Bool
        let uti: AVFileType?
    }

    var imports: (inProgress: Bool, containsManualImports: Bool) {
        // not thread safe access!
        let operations = assetOperations.map({ $0.value.map{ $0.value } }).flatMap{ $0 }
        return (operations.isNotEmpty, operations.contains(where: { $0 is AssetManualImportOperation }))
    }

    unowned let keychainDelegate: KeychainDelegate
    unowned let assetController: AssetController

    let generalOperationQueue = OperationQueue()
    let assetOperationDelegate: AssetOperationDelegateObject
    let photoLibrary: PhotoLibrary
    let iosImageManager = PHImageManager.default()
    let syncTracker = AssetSyncTracker()

    let log = Logger.self
    let assetManagerQueue = DispatchQueue(label: String(describing: AssetManager.self), qos: .default, target: .global())
    let keychainQueue = DispatchQueue(label: String(describing: AssetManager.self) + ".Keychain", qos: .utility, target: DispatchQueue.global())
    var triggerStatusNotification: Closure?

    private unowned let assetDatabase: MutableAssetDatabase
    private weak var networkController: NetworkMonitorController?

    private let primaryUserID: UUID
    private var photoImportQueue = [Asset]()
    private var videoImportQueue = [Asset]()
    private let importOperationQueue = OperationQueue()
    private let downloadOperationQueue = OperationQueue()
    private let deleteOperationQueue = OperationQueue()
    /** [assetid: [operationid: operation]] */
    private var assetOperations = [UUID: [UUID: Operation]]()
    /** [assetid: [operationname: [callback]] */
    private var callbacksForAssetOperations = [UUID: [String: [ClosureBool]]]()
    private var generalOperations = [UUID: AssetManagerOperation]()

    private var autoBackupObserverToken: NSObjectProtocol?
    private var resignActiveObserverToken: NSObjectProtocol?
    private var didBecomeActiveObserverToken: NSObjectProtocol?

    init(primaryUserID: UUID, assetController: AssetController, assetDatabase: MutableAssetDatabase, photoLibrary: PhotoLibrary, keychainDelegate: KeychainDelegate, webAPI: API, dataService: DataService, networkController: NetworkMonitorController?) {
        self.primaryUserID = primaryUserID
        self.assetController = assetController
        self.assetDatabase = assetDatabase
        self.photoLibrary = photoLibrary
        self.keychainDelegate = keychainDelegate
        self.networkController = networkController
        self.assetOperationDelegate = AssetOperationDelegateObject(assetController: assetController, dataService: dataService, webAPI: webAPI, photoLibrary: photoLibrary, keychainQueue: keychainQueue)
        assetOperationDelegate.keychainDelegate = keychainDelegate

        importOperationQueue.qualityOfService = .utility
        downloadOperationQueue.qualityOfService = .userInitiated
        deleteOperationQueue.qualityOfService = .default

        autoBackupObserverToken = NotificationCenter.default.addObserver(forName: .AutoBackupChanged, object: nil, queue: nil) { [unowned self] notification in
            guard let autoBackup = notification.object as? Bool else {
                self.log.error("unrecognised object sent by notification - notification: \(notification.name), object: \(String(describing: notification.object))")
                assertionFailure()
                return
            }
            self.log.verbose("received notification - name: \(notification.name), value: \(autoBackup)")
            if autoBackup {
                self.reloadQueuedImports()
            } else {
                self.assetManagerQueue.async { [weak self] in
                    if photoImportQueue.isNotEmpty {
                        self?.syncTracker.removeTracking(photoImportQueue.map{ $0.uuid })
                        photoImportQueue.removeAll()
                    }
                    if videoImportQueue.isNotEmpty {
                        self?.syncTracker.removeTracking(videoImportQueue.map{ $0.uuid })
                        videoImportQueue.removeAll()
                    }
                    self?.importOperationQueue.cancelAllOperations()
                    self?.importOperationQueue.isSuspended = false
                }
            }
        }

        resignActiveObserverToken = NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: nil) { [unowned self] (_) in
            self.log.verbose("received notification - name: \(UIApplication.willResignActiveNotification)")
            self.assetManagerQueue.async { [weak self] in
                self?.suspendImportOperations(true)
                self?.importOperationQueue.isSuspended = true
                self?.deleteOperationQueue.isSuspended = true
                self?.downloadOperationQueue.isSuspended = true
            }
        }

        didBecomeActiveObserverToken = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: nil) { [unowned self] (_) in
            self.log.verbose("received notification - name: \(UIApplication.didBecomeActiveNotification)")
            self.assetManagerQueue.async { [weak self] in
                self?.downloadOperationQueue.isSuspended = false // always keep download queue unsuspended whenever possible
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
    }
}

// MARK: public functions for app functionality
extension AssetManager {
    func loadAndStartQueues() {
        if UserDefaults.standard.bool(forKey: UserDefaultsKey.AutoBackup.rawValue) {
            reloadQueuedImports()
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
        // check system conditions, pause imports if conditions not met (disk, cloud states, and network photo library access)
        checkSystemFull()

        assetController.allAssets { [weak self] (allAssets) in
            guard let self = self else {
                callback(false)
                return
            }
            let unimportedAssets = allAssets.values.sorted(by: .creationDate(ascending: true)).compactMap{ $0.imported ? nil : $0 }

            var success = true
            let dispatchGroup = DispatchGroup()
            let photoAssets = unimportedAssets.filter{ $0.type == .photo }.suffix(100)
            if photoAssets.isNotEmpty {
                dispatchGroup.enter()
                self.mutableAssets(from: photoAssets.map{ $0.uuid }) { [weak self] (unimportedAssets) in
                    guard let self = self, unimportedAssets.isNotEmpty else {
                        success = success && false
                        dispatchGroup.leave()
                        return
                    }
                    let operation = AssetImportOperation(assets: unimportedAssets, delegate: self)
                    operation.completionBlock = { [weak self, weak operation] in
                        self?.assetManagerQueue.async {
                            defer {
                                dispatchGroup.leave()
                            }
                            guard let self = self, let operation = operation else {
                                success = success && false
                                return
                            }
                            switch operation.currentState {
                            case .some(is AssetImportOperation.Success):
                                success = success && true
                            case .some(is AssetImportOperation.Fatal):
                                self.terminate(assets: unimportedAssets)
                                success = success && true
                            default:
                                success = success && false
                            }
                            self.clear(operation: operation)
                        }
                    }
                    self.queue(operation: operation)
                }
            }
            if let videoAsset = unimportedAssets.last(where: { $0.type == .video }) {
                dispatchGroup.enter()
                self.mutableAssets(from: [videoAsset.uuid]) { [weak self] (unimportedAssets) in
                    guard let self = self, unimportedAssets.isNotEmpty else {
                        success = success && false
                        dispatchGroup.leave()
                        return
                    }
                    let operation = AssetImportOperation(assets: unimportedAssets, delegate: self)
                    operation.completionBlock = { [weak self, weak operation] in
                        self?.assetManagerQueue.async {
                            defer {
                                dispatchGroup.leave()
                            }
                            guard let self = self, let operation = operation else {
                                success = success && false
                                return
                            }
                            switch operation.currentState {
                            case .some(is AssetImportOperation.Success):
                                success = success && true
                            case .some(is AssetImportOperation.Fatal):
                                self.terminate(assets: unimportedAssets)
                                success = success && true
                            default:
                                success = success && false
                            }
                            self.clear(operation: operation)
                        }
                    }
                    self.queue(operation: operation)
                }
            }
            dispatchGroup.notify(queue: .global()) {
                callback(success)
            }
        }
    }

    func cancelBackgroundImports() {
        importOperationQueue.cancelAllOperations()
        importOperationQueue.isSuspended = false
    }
}

// MARK: AssetManager internal functions
extension AssetManager {
    func loadData(for asset: Asset, atQuality quality: Quality, callback: @escaping (Data?, AVFileType?) -> Void) {
        precondition(asset.type == .photo)
        load(asset: asset, atQuality: quality) { [weak self] (url, _, avFileType) in
            if let url = url {
                DispatchQueue.global().async {
                    let data = self?.load(url)
                    DispatchQueue.main.async {
                        callback(data, avFileType)
                    }
                }
            } else {
                DispatchQueue.main.async {
                    callback(nil, avFileType)
                }
            }
        }
    }

    func generateStillImage(forAsset asset: Asset, maxSize: CGSize = .zero, callback: @escaping (UIImage?, AVFileType?) -> Void) {
        precondition(asset.type == .video)
        load(asset: asset, atQuality: .low) { [weak self] (url, _, uti) in
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

    func load(asset: Asset, atQuality quality: Quality, callback: @escaping (URL?, String?, AVFileType?) -> Void) {
        load(assets: [asset], atQuality: quality) { (returnedAsset, url, originalFilename, uti) in
            precondition(returnedAsset == asset)
            callback(url, originalFilename, uti)
        }
    }

    func load<T>(assets: T, atQuality quality: Quality, callback: @escaping (Asset, URL?, String?, AVFileType?) -> Void) where T: Collection, T.Element == Asset {
        let assetsDict = assets.reduce(into: [UUID: Asset]()) {
            $0[$1.uuid] = $1
        }
        mutableAssets(from: assetsDict.keys) { [weak self] (mutableAssets) in
            guard let self = self, mutableAssets.isNotEmpty else {
                return
            }
            self.fetchResources(forAssets: mutableAssets, atQuality: quality) { [weak self] (mutableAsset, success) in
                guard let asset = assetsDict[mutableAsset.uuid] else {
                    assertionFailure()
                    return
                }
                if success {
                    callback(asset, mutableAsset.physicalAssets[quality].localPath, mutableAsset.originalFilename, mutableAsset.originalUTI)
                } else {
                    self?.log.verbose("\(asset.uuid): failed to fetch resource - quality: \(String(describing: quality))")
                    callback(asset, nil, nil, nil)
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
    private func mutableAsset(from assetID: UUID, callback: @escaping (MutableAsset?) -> Void) {
        mutableAssets(from: [assetID]) { [weak self] mutableAssets in
            guard let self = self else { return }
            precondition(.on(self.assetManagerQueue))
            callback(mutableAssets.first)
        }
    }

    private func fetchResources(forAssets assets: [MutableAsset], atQuality quality: Quality, callback: @escaping (MutableAsset, Bool) -> Void) {
        precondition(.on(assetManagerQueue))
        let downloadOperationType = quality == .original ? AssetDownloadOriginalOperation.self : AssetDownloadLowOperation.self
        var assetsToDownload = [MutableAsset]()
        for asset in assets {
            let physicalAsset = asset.physicalAssets[quality]
            if let isReachable = try? physicalAsset.localPath.checkResourceIsReachable(), isReachable {
                callback(asset, true)
            } else if !downloadOperationQueue.isSuspended {
                schedule(callback: ({ (downloaded: Bool) in
                    callback(asset, downloaded)
                }), for: downloadOperationType.lookupKey, onAssetID: asset.uuid)
                assetsToDownload.append(asset)
            } else {
                callback(asset, false)
            }
        }
        if assetsToDownload.isNotEmpty {
            queue(downloadOperationType, for: assetsToDownload)
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
        assetController.remove(assets: assets)
    }
}

// MARK: AssetManager caching functions
private extension AssetManager {
    private func loadMutableAssets<T>(from assetIDs: T, callback: @escaping ([MutableAsset]) -> Void) where T: Collection, T.Element == UUID {
        assetController.mutableAssets(for: assetIDs) { [weak self] (result) in
            var mutableAssets = [MutableAsset]()
            do {
                let result = try result.get()
                result.0.forEach{ $0.database = self?.assetDatabase }
                mutableAssets = result.0
                if result.1.isNotEmpty {
                    self?.syncTracker.removeTracking(result.1)
                }
            } catch {
                self?.log.error(String(describing: error))
                assertionFailure()
            }
            self?.assetManagerQueue.async {
                callback(mutableAssets)
            }
        }
    }
}

// MARK: operation and queing functions
private extension AssetManager {
    private func queue<T>(operation: AssetOperationBatch<T>) where T: MutableAssetProtocol {
        precondition(.on(assetManagerQueue))
        for asset in operation.assets {
            if (assetOperations[asset.uuid]?[operation.id] = operation) == nil {
                assetOperations[asset.uuid] = [operation.id: operation]
            }
        }

        switch operation {
        case is AssetImportOperation:
            importOperationQueue.addOperation(operation)
        case is AssetDownloadOperation:
            downloadOperationQueue.addOperation(operation)
        case is AssetDeleteOperation:
            deleteOperationQueue.addOperation(operation)
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

    private func handleOperationQueues(status: AppContext.Status) {
        importOperationQueue.isSuspended = status.diskSpaceLow || status.cloudSpaceLow || status.networkDown
        deleteOperationQueue.isSuspended = status.networkDown
        if status.diskSpaceLow || status.networkDown {
            downloadOperationQueue.cancelAllOperations()
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

    private func queue(_ downloadOperationType: AssetDownloadOperation.Type, for assets: [MutableAsset]) {
        precondition(.on(assetManagerQueue))
        let assets = assets.filter{ !operationScheduledOrInProgressOfType(downloadOperationType, forAsset: $0) }
        guard assets.isNotEmpty else {
            return
        }
        let operation = downloadOperationType.init(assets: assets, delegate: self)
        operation.completionBlock = { [weak self] in
            self?.assetManagerQueue.async { [weak self] in
                guard let self = self else {
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
            if let importOperation = findScheduledOrInProgressOperationOfType(AssetImportOperation.self, forAsset: asset) {
                deleteOperation.addDependency(importOperation)
            }
            if let downloadOperation = findScheduledOrInProgressOperationOfType(AssetDownloadOriginalOperation.self, forAsset: asset) {
                deleteOperation.addDependency(downloadOperation)
            }
            if let downloadOperation = findScheduledOrInProgressOperationOfType(AssetDownloadLowOperation.self, forAsset: asset) {
                deleteOperation.addDependency(downloadOperation)
            }
        }
        deleteOperation.completionBlock = { [weak self, weak deleteOperation] in
            self?.assetManagerQueue.async {
                guard let self = self, let operation = deleteOperation else {
                    return
                }
                switch operation.currentState.value {
                case .some(.deletedFromDisk):
                    self.terminate(assets: assets)
                case .some(.deletedFromServer):
                    self.deleteOperationQueue.isSuspended = true
                    self.queueNewDeleteOperation(for: assets, state: .deletedFromServer)
                    self.checkSystemFull()
                case .none:
                    self.deleteOperationQueue.isSuspended = true
                    self.queueNewDeleteOperation(for: assets)
                    self.checkSystemFull()
                }
                self.clear(deleteOperation: operation)
            }
        }
        queue(operation: deleteOperation)
    }
}

// MARK: import operation and queing functions
private extension AssetManager {
    private func reloadQueuedImports() {
        assetController.allAssets { [weak self] (allAssets) in
            let unimportedAssets = allAssets.values.sorted(by: .creationDate(ascending: true)).compactMap{ $0.imported ? nil : $0 }
            guard unimportedAssets.isNotEmpty else {
                return
            }
            self?.syncTracker.startTracking(unimportedAssets.map{ $0.uuid })
            let photoImports = unimportedAssets.filter{ $0.type == .photo }
            let videoImports = unimportedAssets.filter{ $0.type == .video }
            self?.assetManagerQueue.async { [weak self] in
                if let self = self {
                    self.photoImportQueue = photoImports
                    self.videoImportQueue = videoImports
                    if self.importOperationQueue.operationCount == 0 {
                        self.scheduleNextBatchOfPhotoImports(batchSize: 5)
                        self.scheduleNextBatchOfVideoImports(batchSize: 1)
                    }
                }
            }
        }
    }

    private func scheduleNextBatchOfPhotoImports(batchSize: Int) {
        precondition(.on(assetManagerQueue))
        let assets: [Asset] = photoImportQueue.suffix(batchSize)
        photoImportQueue = photoImportQueue.dropLast(batchSize)

        scheduleBatchOfImports(forAssets: assets, nextBatch: { [weak self] (assetsToRetry) in
            precondition(.on(self?.assetManagerQueue))
            if let assetsToRetry = assetsToRetry {
                self?.photoImportQueue.insert(contentsOf: assetsToRetry, at: 0)
            }
            self?.scheduleNextBatchOfPhotoImports(batchSize: batchSize)
        })
    }

    private func scheduleNextBatchOfVideoImports(batchSize: Int) {
        precondition(.on(assetManagerQueue))
        let assets: [Asset] = videoImportQueue.suffix(batchSize)
        videoImportQueue = videoImportQueue.dropLast(batchSize)

        scheduleBatchOfImports(forAssets: assets, nextBatch: { [weak self] (assetsToRetry) in
            precondition(.on(self?.assetManagerQueue))
            if let assetsToRetry = assetsToRetry {
                self?.videoImportQueue.insert(contentsOf: assetsToRetry, at: 0)
            }
            self?.scheduleNextBatchOfVideoImports(batchSize: batchSize)
        })
    }

    private func scheduleBatchOfImports(forAssets assets: [Asset], nextBatch: @escaping (_ assetsToRetry: [Asset]?) -> Void) {
        guard assets.isNotEmpty, UserDefaults.standard.bool(forKey: UserDefaultsKey.AutoBackup.rawValue) else {
            return
        }
        mutableAssets(from: assets.map{ $0.uuid }) { [weak self] (mutableAssets) in
            guard let self = self else {
                return
            }
            let mutableAssetsNotImported = self.filterImported(assets: mutableAssets)
            guard mutableAssetsNotImported.isNotEmpty else {
                nextBatch(nil)
                return
            }
            let operation = AssetImportOperation(assets: mutableAssetsNotImported, delegate: self)
            operation.completionBlock = { [weak self] in
                self?.log.debug("Import Operation for \(String(describing: operation.assets.map{ $0.uuid.string })) - finished state: \(String(describing: operation.currentState)), cancelled: \(operation.isCancelled)")

                switch operation.currentState {
                case .some(is AssetImportOperation.Success):
                    self?.completed(importOperation: operation, success: true)
                    self?.checkSystem()
                    self?.assetManagerQueue.async {
                        nextBatch(nil)
                    }
                case .some(let fatalState as AssetImportOperation.Fatal):
                    let fatalAssetIDs = fatalState.assets.map{ $0.uuid }
                    let recoverableAssets = assets.filter{ !fatalAssetIDs.contains($0.uuid) }
                    self?.completed(importOperation: operation, success: false, terminate: fatalState.assets)
                    self?.checkSystem()
                    self?.assetManagerQueue.async {
                        nextBatch(recoverableAssets)
                    }
                case .some, .none:
                    if operation.isCancelled {
                        self?.completed(importOperation: operation, success: false)
                    } else {
                        self?.suspendImports()
                        self?.assetManagerQueue.async {
                            nextBatch(assets)
                        }
                        self?.checkSystemFull()
                    }
                }
                self?.clear(importOperation: operation)
            }
            guard UserDefaults.standard.bool(forKey: UserDefaultsKey.AutoBackup.rawValue) else {
                return
            }
            self.queue(operation: operation)
        }
    }

    private func filterImported(assets: [MutableAsset]) -> [MutableAsset] {
        precondition(.on(assetManagerQueue))
        return assets.filter{ !$0.imported && !operationScheduledOrInProgressOfType(AssetImportOperation.self, forAsset: $0) }
    }

    private func queue(importOperation operation: AssetImportOperation) {
        assetManagerQueue.async { [weak self] in
            self?.queue(operation: operation)
        }
    }

    private func clear(importOperation operation: AssetImportOperation) {
        assetManagerQueue.async { [weak self] in
            self?.clear(operation: operation)
        }
    }

    private func completed(importOperation operation: AssetImportOperation, success: Bool) {
        completed(importOperation: operation, success: success, terminate: nil as [MutableAsset]?)
    }

    private func completed<T>(importOperation operation: AssetImportOperation, success: Bool, terminate: T?) where T: Collection, T.Element == MutableAsset {
        assetManagerQueue.async { [weak self] in
            self?.runCallbacks(for: operation, success: success)
            if let assetsToTerminate = terminate {
                self?.terminate(assets: assetsToTerminate)
            }
        }
    }

    private func suspendImports() {
        importOperationQueue.isSuspended = true
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

    private func checkSystem() {
        triggerStatusNotification?()
    }

    private func checkSystemFull() {
        networkController?.refresh()
    }
}

// MARK: other operation functions
extension AssetManager {
    func createSaveOperation(callback: @escaping (Result<Set<Asset>, Error>) -> Void, progressHandler: ((Int) -> Void)?) -> SaveToLibraryOperation {
        let operation = SaveToLibraryOperation()
        operation.assetController = assetController
        operation.assetManager = self
        operation.photoLibrary = photoLibrary
        operation.progressHandler = progressHandler
        operation.completionBlock = {
            DispatchQueue.main.async {
                if let error = operation.error {
                    callback(.failure(error))
                } else if operation.isCancelled {
                    callback(.failure(OperationError.cancelled))
                } else {
                    callback(.success(operation.alreadySavedAssets))
                }
            }
            self.clearOperation(id: operation.id)
        }
        return operation
    }

    func createRequestOperation(callback: @escaping (Result<[Asset: URL], Error>) -> Void, progressHandler: ((Int) -> Void)?) -> RequestOriginalFileOperation {
        let operation = RequestOriginalFileOperation()
        operation.assetController = assetController
        operation.assetManager = self
        operation.photoLibrary = photoLibrary
        operation.progressHandler = progressHandler
        operation.completionBlock = {
            DispatchQueue.main.async {
                if let error = operation.error {
                    callback(.failure(error))
                } else if operation.isCancelled {
                    callback(.failure(OperationError.cancelled))
                } else {
                    callback(.success(operation.result))
                }
            }
            self.clearOperation(id: operation.id)
        }
        return operation
    }

    func saveOperation(_ operation: AssetManagerOperation) {
        assetManagerQueue.async { [weak self] in
            self?.generalOperations[operation.id] = operation
        }
    }

    func clearOperation(id: UUID) {
        assetManagerQueue.async { [weak self] in
            self?.generalOperations[id] = nil
        }
    }

    func cancelOperation(id: UUID) {
        assetManagerQueue.async { [weak self] in
            self?.generalOperations[id]?.cancel()
        }
    }
}


extension AssetManager: AssetImportManager {
    func priorityImport<T>(_ assets: T, callback: @escaping ClosureBool) where T: Collection, T.Element == Asset {
        let unimportedAssetIDs = assets.filter{ !$0.imported }.map{ $0.uuid }
        guard unimportedAssetIDs.isNotEmpty else {
            callback(true)
            return
        }

        mutableAssets(from: unimportedAssetIDs) { [weak self] (mutableAssets) in
            guard let self = self else {
                return
            }
            let mutableAssetsNotImported = self.filterImported(assets: mutableAssets)
            guard mutableAssetsNotImported.isNotEmpty else {
                DispatchQueue.global().async {
                    callback(true)
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
            for mutableAsset in mutableAssetsNotImported {
                dispatchGroup.enter()
                self.schedule(callback: importRequest, for: AssetImportOperation.lookupKey, onAssetID: mutableAsset.uuid)
            }
            dispatchGroup.notify(queue: .global()) {
                callback(allSuccess)
            }

            let operation = AssetManualImportOperation(assets: mutableAssetsNotImported, delegate: self)
            operation.completionBlock = { [weak self] in
                self?.log.debug("Manual Import Operation for \(String(describing: operation.assets.map{ $0.uuid.string })) - finished state: \(String(describing: operation.currentState)), cancelled: \(operation.isCancelled)")

                switch operation.currentState {
                case .some(is AssetImportOperation.Success):
                    self?.completed(importOperation: operation, success: true)
                case .some(let fatalState as AssetImportOperation.Fatal):
                    self?.completed(importOperation: operation, success: false, terminate: fatalState.assets)
                case .some, .none:
                    self?.completed(importOperation: operation, success: false)
                }
                self?.clear(importOperation: operation)
            }
            operation.queuePriority = .high
            self.queue(operation: operation)
            self.syncTracker.startTracking(mutableAssetsNotImported.map{ $0.uuid })
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

// MARK: functions called directly by UI
extension AssetManager: AssetServiceProvider {
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
                    let iosAssets = iosAssets.values.compactMap{ $0 }
                    guard iosAssets.isNotEmpty else { return }
                    PHPhotoLibrary.shared().performChanges({
                        PHAssetChangeRequest.deleteAssets(iosAssets as NSArray)
                    })  // completionHandler triggers error when denying deletion only on iOS 12
                }
            }
        }
    }

    func save(asset: Asset, callback: @escaping (Result<Bool, Error>) -> Void) -> UUID {
        return save(assets: [asset], callback: { (result) in
            switch result {
            case .success(let alreadySavedAssets):
                callback(.success(alreadySavedAssets.isNotEmpty))
            case .failure(let error):
                callback(.failure(error))
            }
        }, progressHandler: nil)
    }

    func save<T>(assets: T, callback: @escaping (Result<Set<Asset>, Error>) -> Void, progressHandler: ((Int) -> Void)?) -> UUID where T: Collection, T.Element == Asset {
        let operation = createSaveOperation(callback: callback, progressHandler: progressHandler)
        operation.assets = Array(assets)
        saveOperation(operation)
        generalOperationQueue.addOperation(operation)
        return operation.id
    }

    func saveAllAssets(initialCallback: @escaping (Int) -> Void, finalCallback: @escaping (Result<Set<Asset>, Error>) -> Void, progressHandler: @escaping ((Int) -> Void)) -> UUID {
        let operation = createSaveOperation(callback: finalCallback, progressHandler: progressHandler)
        saveOperation(operation)
        assetController.allAssets { [weak self] (allAssets) in
            DispatchQueue.main.async {
                initialCallback(allAssets.count)
            }
            operation.assets = Array(allAssets.values)
            self?.generalOperationQueue.addOperation(operation)
        }
        return operation.id
    }

    func unlinkedAssets(callback: @escaping ([UUID: Asset]) -> Void) {
        assetController.unlinkedAssets { [weak self] (unlinkedAssets: [UUID: Asset]?) in
            guard let self = self, let unlinkedAssets = unlinkedAssets else {
                return
            }
            let ownedUnlinkedAssets = unlinkedAssets.filter{ $0.value.ownerID == self.primaryUserID && $0.value.imported }
            DispatchQueue.main.async {
                callback(ownedUnlinkedAssets)
            }
        }
    }

    func removeAssets<T>(ids: T) where T: Collection, T.Element == UUID {
        self.mutableAssets(from: ids) { [weak self] (mutableAssets) in
            self?.queueNewDeleteOperation(for: mutableAssets)
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
