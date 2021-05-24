//
//  AssetImportQueuingOperation.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 02/03/2021.
//  Copyright © 2021 Vinoth Ramiah. All rights reserved.
//

import Foundation
import GameplayKit.GKState

protocol AssetImportOperationDelegate: AnyObject {
    func mutableAssets<T>(from assetIDs: T, callback: @escaping ([AssetManager.MutableAsset]) -> Void) where T: Collection, T.Element == UUID
    func filterImported(assets: [AssetManager.MutableAsset]) -> [AssetManager.MutableAsset]
    func queue(importOperation operation: AssetManager.AssetImportOperation)
    func clear(importOperation operation: AssetManager.AssetImportOperation)
    func completed(importOperation operation: AssetManager.AssetImportOperation, success: Bool, terminate: Bool)
    func suspendImports()
    func checkSystem()
    func checkSystemFull()
}

extension AssetManager {
    class AssetImportQueuingOperation: AsynchronousOperation {
        weak var delegate: AssetImportOperationDelegate?
        var conditions: () -> Bool = {
            return true
        }

        let assetImportList: AtomicVar<[UUID]>
        private unowned let operationDelegate: AssetOperationDelegate
        private let log = Logger.self
        private let batchSize = 5
        private let concurrentImports = 3

        init(assetImportList: [UUID], operationDelegate: AssetOperationDelegate) {
            self.assetImportList = AtomicVar<[UUID]>(assetImportList)
            self.operationDelegate = operationDelegate
        }

        override func main() {
            super.main()
            let dispatchGroup = DispatchGroup()
            for _ in 1...concurrentImports {
                dispatchGroup.enter()
                processNextBatch(workerGroup: dispatchGroup)
            }
            dispatchGroup.notify(queue: .global()) {
                self.finish()
            }
        }

        func processNextBatch(workerGroup: DispatchGroup) {
            var assetIDs: [UUID]!
            assetImportList.mutate {
                assetIDs = $0.suffix(batchSize)
                if $0.count < batchSize {
                    $0.removeAll()
                } else {
                    $0.removeLast(batchSize)
                }
            }
            guard let delegate = delegate, assetIDs.isNotEmpty, conditions(), !isCancelled else {
                workerGroup.leave()
                return
            }

            delegate.mutableAssets(from: assetIDs) { [weak delegate] mutableAssets in
                guard let delegate = delegate else {
                    workerGroup.leave()
                    return
                }

                let mutableAssetsNotImported = delegate.filterImported(assets: mutableAssets)
                if mutableAssetsNotImported.isNotEmpty {
                    let dispatchGroup = DispatchGroup()
                    dispatchGroup.enter()
                    let operation = self.createAssetImportOperation(for: mutableAssetsNotImported, dispatchGroup: dispatchGroup)
                    delegate.queue(importOperation: operation)
                    dispatchGroup.notify(queue: .global()) {
                        self.processNextBatch(workerGroup: workerGroup)
                    }
                } else {
                    self.processNextBatch(workerGroup: workerGroup)
                }
            }
        }

        func createAssetImportOperation(for assets: [MutableAsset], dispatchGroup: DispatchGroup, state: GKState.Type? = nil) -> AssetImportOperation {
            let operation = AssetImportOperation(assets: assets, delegate: operationDelegate, currentState: state)
            operation.completionBlock = { [weak self, weak operation] in
                guard let self = self, let delegate = self.delegate, let operation = operation else {
                    dispatchGroup.leave()
                    return
                }

                self.log.debug("Import Operation for \(String(describing: operation.assets.map{ $0.uuid.string })) - finished state: \(String(describing: operation.currentState)), cancelled: \(operation.isCancelled)")

                switch operation.currentState {
                case .some(is AssetImportOperation.Success):
                    delegate.completed(importOperation: operation, success: true, terminate: false)
                    delegate.checkSystem()
                    dispatchGroup.leave()
                case .some(is AssetImportOperation.Fatal):
                    delegate.completed(importOperation: operation, success: false, terminate: true)
                    delegate.checkSystem()
                    dispatchGroup.leave()
                case .some(let state):
                    if operation.isCancelled {
                        delegate.completed(importOperation: operation, success: false, terminate: false)
                        dispatchGroup.leave()
                    } else {
                        delegate.suspendImports()
                        let replacementOperation = self.createAssetImportOperation(for: assets, dispatchGroup: dispatchGroup, state: type(of: state))
                        delegate.queue(importOperation: replacementOperation)
                        delegate.checkSystemFull()
                    }
                case .none:
                    if operation.isCancelled {
                        delegate.completed(importOperation: operation, success: false, terminate: false)
                        dispatchGroup.leave()
                    } else {
                        delegate.suspendImports()
                        let replacementOperation = self.createAssetImportOperation(for: assets, dispatchGroup: dispatchGroup)
                        delegate.queue(importOperation: replacementOperation)
                        delegate.checkSystemFull()
                    }
                }
                delegate.clear(importOperation: operation)
            }
            return operation
        }
    }

    class AssetManualImportQueuingOperation: AssetImportQueuingOperation {
        override func createAssetImportOperation(for assets: [AssetManager.MutableAsset], dispatchGroup: DispatchGroup, state: GKState.Type? = nil) -> AssetManager.AssetImportOperation {
            let operation = super.createAssetImportOperation(for: assets, dispatchGroup: dispatchGroup, state: state)
            operation.queuePriority = .high
            return operation
        }
    }
}
