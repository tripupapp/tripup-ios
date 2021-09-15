//
//  AssetServiceProvider.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 15/09/2021.
//  Copyright © 2021 Vinoth Ramiah. All rights reserved.
//

import Foundation

protocol AssetServiceProvider: AnyObject {
    func delete<T>(_ assets: T) where T: Collection, T.Element == Asset
    func save(asset: Asset, callback: @escaping (Result<Bool, Error>) -> Void) -> UUID
    func save<T>(assets: T, callback: @escaping (Result<Set<Asset>, Error>) -> Void, progressHandler: ((Int) -> Void)?) -> UUID where T: Collection, T.Element == Asset
    func saveAllAssets(initialCallback: @escaping (Int) -> Void, finalCallback: @escaping (Result<Set<Asset>, Error>) -> Void, progressHandler: @escaping ((Int) -> Void)) -> UUID
    func cancelOperation(id: UUID)
    func unlinkedAssets(callback: @escaping ([UUID: Asset]) -> Void)
    func removeAssets<T>(ids: T) where T: Collection, T.Element == UUID
}
