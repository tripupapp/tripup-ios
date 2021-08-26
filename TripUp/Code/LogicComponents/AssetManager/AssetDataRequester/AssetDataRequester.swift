//
//  AssetDataRequester.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 18/08/2020.
//  Copyright © 2020 Vinoth Ramiah. All rights reserved.
//

import Foundation
import struct AVFoundation.AVFileType

protocol AssetDataRequester: AssetImageRequester, AssetAVRequester {
    func requestOriginalFile(forAsset asset: Asset, callback: @escaping (Result<URL, Error>) -> Void) -> UUID
    func requestOriginalFiles(forAssets assets: [Asset], callback: @escaping (Result<[Asset: URL], Error>) -> Void, progressHandler: ((Int) -> Void)?) -> UUID
    func cancelRequestOriginalOperation(id: UUID)
}

extension AssetManager: AssetDataRequester {
    func requestOriginalFiles(forAssets assets: [Asset], callback: @escaping (Result<[Asset: URL], Error>) -> Void, progressHandler: ((Int) -> Void)?) -> UUID {
        let operation = RequestOriginalFileOperation()
        operation.assetController = assetController
        operation.assetManager = self
        operation.photoLibrary = photoLibrary
        operation.assets = assets
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
        }
        generalOperationQueue.addOperation(operation)
        return operation.id
    }

    func requestOriginalFile(forAsset asset: Asset, callback: @escaping (Result<URL, Error>) -> Void) -> UUID {
        return requestOriginalFiles(forAssets: [asset], callback: { (result) in
            switch result {
            case .success(let dict):
                callback(.success(dict.first!.value))
            case .failure(let error):
                callback(.failure(error))
            }
        }, progressHandler: nil)
    }

    func cancelRequestOriginalOperation(id: UUID) {
        let requestOperation = generalOperationQueue.operations.first { (operation) -> Bool in
            if let requestOperation = operation as? RequestOriginalFileOperation {
                return requestOperation.id == id
            }
            return false
        }
        requestOperation?.cancel()
    }
}
