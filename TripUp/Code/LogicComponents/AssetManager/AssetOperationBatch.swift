//
//  AssetOperationBatch.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 22/02/2021.
//  Copyright © 2021 Vinoth Ramiah. All rights reserved.
//

import Foundation
import GameplayKit.GKState

extension AssetManager {
    class AssetOperationBatch<Asset: MutableAssetProtocol>: AsynchronousOperation {
        class var lookupKey: String {
            return String(describing: self)
        }

        let id = UUID()
        let assets: [Asset]

        fileprivate unowned let delegate: AssetOperationDelegate
        fileprivate let operationQueue = OperationQueue()
        fileprivate var operations = [Operation]()

        init(assets: [Asset], delegate: AssetOperationDelegate) {
            self.assets = assets
            self.delegate = delegate
            super.init()
        }

        override func cancel() {
            operationQueue.cancelAllOperations()
            super.cancel()
        }

        func suspend(_ value: Bool) {
            operations.forEach{ ($0 as? AssetOperationBatch)?.suspend(value) }
            operationQueue.isSuspended = value
        }
    }
}

extension AssetManager {
    class AssetImportOperation: AssetOperationBatch<AssetManager.MutableAsset> {
        class KeyGenerated: GKState {}
        class FetchedFromIOS: GKState {}
        class UploadedToCloud: GKState {}
        class Success: GKState {
            override func isValidNextState(_ stateClass: AnyClass) -> Bool {
                return false
            }
        }
        class Fatal: GKState {
            weak var operationQueue: OperationQueue?
            var assets = Set<MutableAsset>()

            override func didEnter(from previousState: GKState?) {
                operationQueue?.cancelAllOperations()
            }

            override func isValidNextState(_ stateClass: AnyClass) -> Bool {
                return false
            }
        }

        var currentState: GKState? {
            return stateMachine.currentStateSynced
        }

        private let log = Logger.self
        private let stateMachine: SynchronizedStateMachine

        init(assets: [MutableAsset], delegate: AssetOperationDelegate, currentState: GKState.Type? = nil) {
            let states = [
                KeyGenerated(),
                FetchedFromIOS(),
                UploadedToCloud(),
                Success(),
                Fatal()
            ]
            self.stateMachine = SynchronizedStateMachine(states: states)
            super.init(assets: assets, delegate: delegate)

            stateMachine.state(forClass: Fatal.self)?.operationQueue = operationQueue
            if let currentState = currentState {
                stateMachine.enter(currentState)
            }
        }

        override func main() {
            super.main()
            log.debug("Begin Import Operation for \(assets.map{ $0.uuid.string })")

            var opGen: GenerateEncryptionKey?
            var opFetch: FetchFromIOS?
            var cloudCompletionOp: BlockOperationWithResult?

            switch stateMachine.currentStateSynced {
            case .none:
                opGen = GenerateEncryptionKey(assets: assets, delegate: delegate)
                opGen?.completionBlock = { [weak self, weak operation = opGen] in
                    guard let result = operation?.result else {
                        return
                    }
                    switch result {
                    case .success(_):
                        self?.stateMachine.enter(KeyGenerated.self)
                    case .failure(.notRun):
                        break
                    case .failure(.recoverable):
                        break
                    case .failure(.fatal(let asset)):
                        self?.stateMachine.state(forClass: Fatal.self)?.assets.insert(asset)
                        self?.stateMachine.enter(Fatal.self)
                    }
                }
                operations.append(opGen!)
                fallthrough
            case .some(is KeyGenerated):
                opFetch = FetchFromIOS(assets: assets, delegate: delegate)
                opFetch?.completionBlock = { [weak self, weak operation = opFetch] in
                    guard let result = operation?.result else {
                        return
                    }
                    switch result {
                    case .success(_):
                        self?.stateMachine.enter(FetchedFromIOS.self)
                    case .failure(.notRun):
                        break
                    case .failure(.recoverable):
                        break
                    case .failure(.fatal(let asset)):
                        self?.stateMachine.state(forClass: Fatal.self)?.assets.insert(asset)
                        self?.stateMachine.enter(Fatal.self)
                    }
                }
                if let opGen = opGen {
                    opFetch?.addDependency(opGen)
                }
                operations.append(opFetch!)
                fallthrough
            case .some(is FetchedFromIOS):
                let opDataUploadLow = AssetUploadOperation(assets: assets.map{ $0.physicalAssets.low }, delegate: delegate)
                opDataUploadLow.completionBlock = { [weak self, weak operation = opDataUploadLow] in
                    if case .some(.failure(.fatal(let asset))) = operation?.result {
                        self?.stateMachine.state(forClass: Fatal.self)?.assets.insert(asset)
                        self?.stateMachine.enter(Fatal.self)
                    }
                }
                if let opFetch = opFetch {
                    opDataUploadLow.addDependency(opFetch)
                }
                operations.append(opDataUploadLow)

                let opDataUploadOriginal = AssetUploadOperation(assets: assets.map{ $0.physicalAssets.original }, delegate: delegate)
                opDataUploadOriginal.completionBlock = { [weak self, weak operation = opDataUploadOriginal] in
                    if case .some(.failure(.fatal(let asset))) = operation?.result {
                        self?.stateMachine.state(forClass: Fatal.self)?.assets.insert(asset)
                        self?.stateMachine.enter(Fatal.self)
                    }
                }
                if let opFetch = opFetch {
                    opDataUploadOriginal.addDependency(opFetch)
                }
                operations.append(opDataUploadOriginal)

                cloudCompletionOp = BlockOperationWithResult()
                cloudCompletionOp?.addExecutionBlock { [weak self, weak operation = cloudCompletionOp, weak opDataUploadLow, weak opDataUploadOriginal] in
                    if case .some(.success(_)) = opDataUploadLow?.result, case .some(.success(_)) = opDataUploadOriginal?.result {
                        operation?.result = .success(nil)
                        self?.stateMachine.enter(UploadedToCloud.self)
                    }
                }
                cloudCompletionOp?.addDependency(opDataUploadLow)
                cloudCompletionOp?.addDependency(opDataUploadOriginal)
                operations.append(cloudCompletionOp!)

                fallthrough
            case .some(is UploadedToCloud):
                let createOnServerOp = CreateOnServer(assets: assets, delegate: delegate)
                createOnServerOp.completionBlock = { [weak self, weak operation = createOnServerOp] in
                    defer {
                        self?.log.debug("End Import Operation for \(String(describing: self?.assets.map{ $0.uuid.string }))")
                        self?.finish()
                    }
                    guard let result = operation?.result else {
                        return
                    }
                    switch result {
                    case .success(_):
                        self?.stateMachine.enter(Success.self)
                    case .failure(.notRun):
                        break
                    case .failure(.recoverable):
                        break
                    case .failure(.fatal(let asset)):
                        self?.stateMachine.state(forClass: Fatal.self)?.assets.insert(asset)
                        self?.stateMachine.enter(Fatal.self)
                    }
                }
                if let cloudCompletionOp = cloudCompletionOp {
                    createOnServerOp.addDependency(cloudCompletionOp)
                }
                operations.append(createOnServerOp)

                operationQueue.addOperations(operations, waitUntilFinished: false)
            case .some(is Success):
                log.debug("End Import Operation for \(assets.map{ $0.uuid.string })")
                assert(assets.allSatisfy{ $0.imported && $0.cloudFilesize != 0 })
                finish()
            case .some(is Fatal):
                log.debug("End Import Operation for \(assets.map{ $0.uuid.string })")
                assertionFailure()
                finish()
            default:
                fatalError(String(describing: stateMachine.currentStateSynced))
            }
        }
    }

    class AssetDeleteOperation: AssetOperationBatch<AssetManager.MutableAsset> {
        enum State {
            case deletedFromServer
            case deletedFromDisk
        }

        let currentState: AtomicVar<State?>
        private let log = Logger.self

        init(assets: [MutableAsset], delegate: AssetOperationDelegate, currentState: State? = nil) {
            self.currentState = AtomicVar<State?>(currentState)
            super.init(assets: assets, delegate: delegate)
        }

        override func main() {
            super.main()
            for dependency in dependencies {
                if let dependency = dependency as? AssetImportOperation {
                    guard dependency.currentState is AssetImportOperation.Success else {
                        finish()
                        return
                    }
                }
            }

            var opDeleteFromDB: DeleteFromDB?
            var opDeleteFromDisk: BlockOperation?

            switch currentState.value {
            case .none:
                opDeleteFromDB = DeleteFromDB(assets: assets, delegate: delegate)
                opDeleteFromDB?.completionBlock = { [weak self, weak operation = opDeleteFromDB] in
                    if case .some(.success(_)) = operation?.result {
                        self?.currentState.mutate{ $0 = .deletedFromServer }
                    }
                }
                operations.append(opDeleteFromDB!)
                fallthrough
            case .some(.deletedFromServer):
                opDeleteFromDisk = BlockOperation(block: { [weak self, weak dependency = opDeleteFromDB] in
                    guard let self = self else {
                        return
                    }
                    defer {
                        self.finish()
                    }
                    if let dependency = dependency {
                        guard case .success(_) = dependency.result else {
                            return
                        }
                    }

                    for asset in self.assets {
                        asset.physicalAssets.low.remotePath = nil
                        asset.physicalAssets.original.remotePath = nil
                        guard self.delegate.delete(resourceAt: asset.physicalAssets.low.localPath) else {
                            self.log.error("\(asset.uuid.string): failed to delete file – localPath: \(String(describing: asset.physicalAssets.low.localPath))")
                            return
                        }
                        guard self.delegate.delete(resourceAt: asset.physicalAssets.original.localPath) else {
                            self.log.error("\(asset.uuid.string): failed to delete file – localPath: \(String(describing: asset.physicalAssets.original.localPath))")
                            return
                        }
                    }
                    self.currentState.mutate{ $0 = .deletedFromDisk }
                })
                if let opDeleteFromDB = opDeleteFromDB {
                    opDeleteFromDisk?.addDependency(opDeleteFromDB)
                }
                operations.append(opDeleteFromDisk!)

                operationQueue.addOperations(operations, waitUntilFinished: false)
            case .some(.deletedFromDisk):
                finish()
            }
        }
    }

    class AssetUploadOperation: AssetOperationBatch<AssetManager.MutablePhysicalAsset> {
        var result: ResultType = .failure(.notRun)

        override func main() {
            super.main()
            for dependency in dependencies {
                if let dependency = dependency as? AssetOperationResult {
                    guard case .success = dependency.result else {
                        finish()
                        return
                    }
                }
            }

            var opCompress: CompressData?
            if assets.contains(where: { $0.quality == .low }) {
                precondition( assets.allSatisfy{ $0.quality == .low } )
                opCompress = CompressData(assets: assets, delegate: delegate)
                operations.append(opCompress!)
            }

            let opEncrypt = EncryptData(assets: assets, delegate: delegate)
            if let opCompress = opCompress {
                opEncrypt.addDependency(opCompress)
            }
            operations.append(opEncrypt)

            let opUpload = UploadData(assets: assets, delegate: delegate)
            opUpload.addDependency(opEncrypt)
            operations.append(opUpload)

            let finalResult = BlockOperation { [weak self] in
                guard let self = self else {
                    return
                }
                for operation in self.operations {
                    if let operation = operation as? AssetOperationResult, case .failure(_) = operation.result {
                        self.result = operation.result
                        return
                    }
                }
                self.result = .success(nil)
            }
            finalResult.completionBlock = { [weak self] in
                self?.finish()
            }
            finalResult.addDependency(opUpload)
            operations.append(finalResult)

            operationQueue.addOperations(operations, waitUntilFinished: false)
        }
    }

    class AssetDownloadOperation: AssetOperationBatch<AssetManager.MutablePhysicalAsset> {
        var result: ResultType = .failure(.notRun)

        override func main() {
            super.main()
            let opDownload = DownloadData(assets: assets, delegate: delegate)
            operations.append(opDownload)

            let opDecrypt = DecryptData(assets: assets, delegate: delegate)
            opDecrypt.addDependency(opDownload)
            operations.append(opDecrypt)

            let finalResult = BlockOperation { [weak self] in
                guard let self = self else {
                    return
                }
                for operation in self.operations {
                    if let operation = operation as? AssetOperationResult, case .failure(_) = operation.result {
                        self.result = operation.result
                        return
                    }
                }
                self.result = .success(nil)
            }
            finalResult.completionBlock = { [weak self] in
                self?.finish()
            }
            finalResult.addDependency(opDecrypt)
            operations.append(finalResult)

            operationQueue.addOperations(operations, waitUntilFinished: false)
        }
    }

    class BlockOperationWithResult: BlockOperation, AssetOperationResult {
        var result: ResultType = .failure(.notRun)
    }
}

extension AssetManager.AssetUploadOperation: AssetOperationResult {}

extension AssetManager.AssetDownloadOperation: AssetOperationResult {}
