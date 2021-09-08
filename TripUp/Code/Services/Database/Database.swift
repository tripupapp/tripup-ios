//
//  Database.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 30/09/2019.
//  Copyright © 2019 Vinoth Ramiah. All rights reserved.
//

import Foundation

protocol Database: GroupDatabase, AssetDatabase, UserDatabase {
    func configure()
    func clear()
}

protocol GroupDatabase: AnyObject {
    var allGroups: [UUID: Group] { get }
    func lookup(_ id: UUID) -> Group?
    func addGroup(_ group: Group) throws
    func removeGroup(_ group: Group) throws
    func updateGroup(id: UUID, assetIDs: [UUID], sharedAssetIDs: [UUID]) throws -> Group
    func addUsers<T>(withIDs userIDs: T, toGroupID groupID: UUID) throws -> Group where T: Collection, T.Element == UUID
    func removeUsers<T>(withIDs userIDs: T, fromGroupID groupID: UUID) throws -> Group where T: Collection, T.Element == UUID
    func addAssets<T>(ids assetIDs: T, toGroupID groupID: UUID) throws -> Group where T: Collection, T.Element == UUID
    func removeAssets<T>(ids assetIDs: T, fromGroupID groupID: UUID) throws -> Group where T: Collection, T.Element == UUID
    func shareAssets<T>(ids assetIDs: T, withGroupID groupID: UUID) throws -> Group where T: Collection, T.Element == UUID
    func unshareAssets<T>(ids assetIDs: T, fromGroupID groupID: UUID) throws -> Group where T: Collection, T.Element == UUID
}

protocol AssetDatabase: AnyObject {
    var allAssets: [UUID: Asset] { get }
    var assetIDLocalIDMap: [UUID: String] { get }
    var cloudStorageUsed: UsedStorage? { get }
    var deletedAssetIDs: [UUID]? { get }

    func mutableAssets<T, U>(forAssetIDs assetIDs: T) throws -> U where T: Collection, T.Element == UUID, U: ArrayOrSet, U.Element == AssetManager.MutableAsset
    func unlinkedAsset(withMD5Hash md5: Data) -> AssetManager.MutableAsset?
    func unlinkedAssets() -> [UUID: Asset]?
    func fingerprint(forAssetID assetID: UUID) throws -> String?
    func save(fingerprint: String, forAssetID assetID: UUID) throws
    func filename(forAssetID assetID: UUID) throws -> String?
    func save(filename: String, forAssetID assetID: UUID) throws
    func uti(forAssetID assetID: UUID) throws -> String?
    func save(uti: String, forAssetID assetID: UUID) throws
    func localIdentifiers<T>(forAssetIDs assetIDs: T) throws -> [UUID: String] where T: Collection, T.Element == UUID
    func save(localIdentifier: String?, forAssetID assetID: UUID) throws
    func saveLocalIdentifiers(assetIDs2LocalIDs: [String: String]) throws
    func `switch`(localIdentifier: String, fromAssetID oldAssetID: UUID, toAssetID newAssetID: UUID) throws
    func md5(forAssetID assetID: UUID) throws -> Data?
    func save(md5: Data, forAssetID assetID: UUID) throws
    func cloudFilesize(forAssetID assetID: UUID) throws -> UInt64
    func save(cloudFilesize: UInt64, forAssetID assetID: UUID) throws
    func importStatus(forAssetID assetID: UUID) throws -> Bool
    func save(importStatus: Bool, forAssetID assetID: UUID) throws -> ((Asset, Asset), [(Group, Group)]?)
    func deleteStatus(forAssetID assetID: UUID) throws -> Bool
    func save(deleteStatus: Bool, forAssetID assetID: UUID) throws -> ((Asset, Asset), [(Group, Group)]?)
    func remotePath(forAssetID assetID: UUID, atQuality quality: AssetManager.Quality) throws -> URL?
    func save(remotePath: URL?, forAssetID assetID: UUID, atQuality quality: AssetManager.Quality) throws

    func pruneLocalIDs(forAssetIDs assetIDs: [UUID]) throws
    func sync<T>(_ data: [UUID: [String: Any]], withAssetIDs assetIDs: T) throws -> ([Asset]?, [(Group, Group)]?) where T: Collection, T.Element == UUID

    func addLocalAssets<T>(_ assets: T) throws where T: Collection, T.Element == (Asset, String)
    func addRemoteAssets(from decryptedData: [UUID: [String: Any?]], serverData: [UUID: [String: Any]]) throws -> [Asset]
    func remove<T>(assetIDs: T) throws -> [(Group, Group)]? where T: Collection, T.Element == UUID
}

protocol UserDatabase: AnyObject {
    var allUsers: [UUID: User] { get }
    func lookup(_ id: UUID) -> User?
    func add<T>(_ users: T) throws where T: Collection, T.Element == User
    func remove<T>(userIDs: T) throws -> [Group] where T: Collection, T.Element == UUID
    func update(_ localContact: Data?, forUserID userID: UUID) throws -> (User, [Group])
}

enum DatabaseError: Error, LocalizedError {
    case recordDoesNotExist(type: Any, id: UUID)
    case recordAlreadyExists
    case recordNotLinked
    case recordAlreadyLinked
    case recordCountMismatch(expected: Int, actual: Int)
    case unexpectedError
}
