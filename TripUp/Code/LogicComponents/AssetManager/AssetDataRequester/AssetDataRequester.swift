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
    func cancelOperation(id: UUID)
}

extension AssetManager: AssetDataRequester {
    func requestOriginalFiles(forAssets assets: [Asset], callback: @escaping (Result<[Asset: URL], Error>) -> Void, progressHandler: ((Int) -> Void)?) -> UUID {
        let operation = createRequestOperation(callback: callback, progressHandler: progressHandler)
        operation.assets = assets
        saveOperation(operation)
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
}
