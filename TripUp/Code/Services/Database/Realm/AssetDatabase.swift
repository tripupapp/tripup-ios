//
//  AssetDatabase.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 30/09/2019.
//  Copyright © 2019 Vinoth Ramiah. All rights reserved.
//

import Foundation
import RealmSwift

extension RealmDatabase: AssetDatabase {
    var allAssets: [UUID: Asset] {
        autoreleasepool {
            guard let realm = try? Realm() else { return [UUID: Asset]() }
            let assetObjects = realm.objects(AssetObject.self)
            let assets = assetObjects.map{ Asset(from: $0) }
            return assets.reduce(into: [UUID: Asset]()) {
                $0[$1.uuid] = $1
            }
        }
    }

    var assetIDLocalIDMap: [UUID: String] {
        autoreleasepool {
            guard let realm = try? Realm() else { return [UUID: String]() }
            let assetObjects: Results<AssetObject> = realm.objects(AssetObject.self).filter(NSPredicate(format: "%K != nil", #keyPath(AssetObject.localIdentifier)))
            var mapping = [UUID: String]()
            for assetObject in assetObjects {
                mapping[UUID(uuidString: assetObject.uuid)!] = assetObject.localIdentifier
            }
            return mapping
        }
    }

    var cloudStorageUsed: UsedStorage? {
        autoreleasepool {
            guard let realm = try? Realm() else { return nil }
            let importedItems = realm.objects(AssetObject.self).filter(NSPredicate(format: "%K == true", #keyPath(AssetObject.imported)))
            let photos = importedItems.filter(NSPredicate(format: "%K == %@", #keyPath(AssetObject.type), AssetType.photo.rawValue))
            let videos = importedItems.filter(NSPredicate(format: "%K == %@", #keyPath(AssetObject.type), AssetType.video.rawValue))
            let photosSize: Int64 = photos.sum(ofProperty: #keyPath(AssetObject.totalSize))
            let videosSize: Int64 = videos.sum(ofProperty: #keyPath(AssetObject.totalSize))
            return UsedStorage(
                photos: (count: photos.count, totalSize: photosSize),
                videos: (count: videos.count, totalSize: videosSize)
            )
        }
    }

    var deletedAssetIDs: [UUID]? {
        autoreleasepool {
            guard let realm = try? Realm() else {
                return nil
            }
            return realm.objects(AssetObject.self).filter(NSPredicate(format: "%K == true", #keyPath(AssetObject.deleted))).map{ UUID(uuidString: $0.uuid)! }
        }
    }

    func mutableAssets<T, U>(forAssetIDs assetIDs: T) throws -> U where T: Collection, T.Element == UUID, U: ArrayOrSet, U.Element == AssetManager.MutableAsset {
        try autoreleasepool {
            let realm = try Realm()
            let imageObjects: Results<AssetObject> = try query(assetIDs, from: realm, exact: false)
            return U(imageObjects.map{ AssetManager.MutableAsset(from: $0) })
        }
    }

    func unlinkedAsset(withMD5Hash md5: Data) -> Asset? {
        autoreleasepool {
            guard let realm = try? Realm() else { return nil }
            let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "%K == %@", #keyPath(AssetObject.md5), md5 as NSData),
                NSPredicate(format: "%K == nil", #keyPath(AssetObject.localIdentifier))
            ])
            let objects = realm.objects(AssetObject.self).filter(predicate)
            if let object = objects.first {
                return Asset(from: object)
            } else {
                return nil
            }
        }
    }

    func unlinkedAssets() -> [UUID: Asset]? {
        autoreleasepool {
            guard let realm = try? Realm() else {
                return nil
            }
            let predicate = NSPredicate(format: "%K == nil", #keyPath(AssetObject.localIdentifier))
            let objects = realm.objects(AssetObject.self).filter(predicate)
            let assets = objects.map{ Asset(from: $0) }
            return assets.reduce(into: [UUID: Asset]()) {
                $0[$1.uuid] = $1
            }
        }
    }

    func fingerprint(forAssetID assetID: UUID) throws -> String? {
        try autoreleasepool {
            let realm = try Realm()
            guard let imageObject = realm.object(ofType: AssetObject.self, forPrimaryKey: assetID.string) else {
                throw DatabaseError.recordDoesNotExist(type: AssetObject.self, id: assetID)
            }
            return imageObject.fingerprint
        }
    }

    func save(fingerprint: String, forAssetID assetID: UUID) throws {
        try autoreleasepool {
            let realm = try Realm()
            guard let imageObject = realm.object(ofType: AssetObject.self, forPrimaryKey: assetID.string) else {
                throw DatabaseError.recordDoesNotExist(type: AssetObject.self, id: assetID)
            }
            try realm.write {
                imageObject.fingerprint = fingerprint
            }
        }
    }

    func filename(forAssetID assetID: UUID) throws -> String? {
        try autoreleasepool {
            let realm = try Realm()
            guard let assetObject = realm.object(ofType: AssetObject.self, forPrimaryKey: assetID.string) else {
                throw DatabaseError.recordDoesNotExist(type: AssetObject.self, id: assetID)
            }
            return assetObject.originalFilename
        }
    }

    func save(filename: String, forAssetID assetID: UUID) throws {
        try autoreleasepool {
            let realm = try Realm()
            guard let assetObject = realm.object(ofType: AssetObject.self, forPrimaryKey: assetID.string) else {
                throw DatabaseError.recordDoesNotExist(type: AssetObject.self, id: assetID)
            }
            try realm.write {
                assetObject.originalFilename = filename
            }
        }
    }

    func uti(forAssetID assetID: UUID) throws -> String? {
        try autoreleasepool {
            let realm = try Realm()
            guard let imageObject = realm.object(ofType: AssetObject.self, forPrimaryKey: assetID.string) else {
                throw DatabaseError.recordDoesNotExist(type: AssetObject.self, id: assetID)
            }
            return imageObject.originalUTI
        }
    }

    func save(uti: String, forAssetID assetID: UUID) throws {
        try autoreleasepool {
            let realm = try Realm()
            guard let imageObject = realm.object(ofType: AssetObject.self, forPrimaryKey: assetID.string) else {
                throw DatabaseError.recordDoesNotExist(type: AssetObject.self, id: assetID)
            }
            try realm.write {
                imageObject.originalUTI = uti
            }
        }
    }

    func localIdentifiers<T>(forAssetIDs assetIDs: T) throws -> [UUID: String] where T: Collection, T.Element == UUID {
        try autoreleasepool {
            let realm = try Realm()
            let assetObjects: Results<AssetObject> = try query(assetIDs, from: realm)
            return assetObjects.reduce(into: [UUID: String]()) {
                $0[UUID(uuidString: $1.uuid)!] = $1.localIdentifier
            }
        }
    }

    func save(localIdentifier: String?, forAssetID assetID: UUID) throws {
        try autoreleasepool {
            let realm = try Realm()
            guard let imageObject = realm.object(ofType: AssetObject.self, forPrimaryKey: assetID.string) else {
                throw DatabaseError.recordDoesNotExist(type: AssetObject.self, id: assetID)
            }
            try realm.write {
                imageObject.localIdentifier = localIdentifier
            }
        }
    }

    func saveLocalIdentifiers(assetIDs2LocalIDs: [String: String]) throws {
        try autoreleasepool {
            let realm = try Realm()
            let assetObjects: Results<AssetObject> = try query(assetIDs2LocalIDs.keys, from: realm)
            try realm.write {
                assetObjects.forEach{ $0.localIdentifier = assetIDs2LocalIDs[$0.uuid] }
            }
        }
    }

    func `switch`(localIdentifier: String, fromAssetID oldAssetID: UUID, toAssetID newAssetID: UUID) throws {
        try autoreleasepool {
            let realm = try Realm()
            guard let oldAssetObject = realm.object(ofType: AssetObject.self, forPrimaryKey: oldAssetID.string) else {
                throw DatabaseError.recordDoesNotExist(type: AssetObject.self, id: oldAssetID)
            }
            guard let newAssetObject = realm.object(ofType: AssetObject.self, forPrimaryKey: newAssetID.string) else {
                throw DatabaseError.recordDoesNotExist(type: AssetObject.self, id: newAssetID)
            }
            guard oldAssetObject.localIdentifier == localIdentifier else {
                throw DatabaseError.recordNotLinked
            }
            guard newAssetObject.localIdentifier == nil else {
                throw DatabaseError.recordAlreadyLinked
            }
            try realm.write {
                oldAssetObject.localIdentifier = nil
                newAssetObject.localIdentifier = localIdentifier
            }
        }
    }

    func md5(forAssetID assetID: UUID) throws -> Data? {
        try autoreleasepool {
            let realm = try Realm()
            guard let imageObject = realm.object(ofType: AssetObject.self, forPrimaryKey: assetID.string) else {
                throw DatabaseError.recordDoesNotExist(type: AssetObject.self, id: assetID)
            }
            return imageObject.md5
        }
    }

    func save(md5: Data, forAssetID assetID: UUID) throws {
        try autoreleasepool {
            let realm = try Realm()
            guard let imageObject = realm.object(ofType: AssetObject.self, forPrimaryKey: assetID.string) else {
                throw DatabaseError.recordDoesNotExist(type: AssetObject.self, id: assetID)
            }
            try realm.write {
                imageObject.md5 = md5
            }
        }
    }

    func cloudFilesize(forAssetID assetID: UUID) throws -> UInt64 {
        try autoreleasepool {
            let realm = try Realm()
            guard let imageObject = realm.object(ofType: AssetObject.self, forPrimaryKey: assetID.string) else {
                throw DatabaseError.recordDoesNotExist(type: AssetObject.self, id: assetID)
            }
            return UInt64(imageObject.totalSize)
        }
    }

    func save(cloudFilesize: UInt64, forAssetID assetID: UUID) throws {
        guard let size = Int64(exactly: cloudFilesize) else { fatalError("unable to convert UInt64 to Int64. value: \(cloudFilesize)") }  // Realm only supports Int64, not UInt64
        try autoreleasepool {
            let realm = try Realm()
            guard let imageObject = realm.object(ofType: AssetObject.self, forPrimaryKey: assetID.string) else {
                throw DatabaseError.recordDoesNotExist(type: AssetObject.self, id: assetID)
            }
            try realm.write {
                imageObject.totalSize = size
            }
        }
    }

    func importStatus(forAssetID assetID: UUID) throws -> Bool {
        try autoreleasepool {
            let realm = try Realm()
            guard let imageObject = realm.object(ofType: AssetObject.self, forPrimaryKey: assetID.string) else {
                throw DatabaseError.recordDoesNotExist(type: AssetObject.self, id: assetID)
            }
            return imageObject.imported
        }
    }

    func save(importStatus: Bool, forAssetID assetID: UUID) throws -> ((Asset, Asset), [(Group, Group)]?) {
        try autoreleasepool {
            let realm = try Realm()
            guard let imageObject = realm.object(ofType: AssetObject.self, forPrimaryKey: assetID.string) else {
                throw DatabaseError.recordDoesNotExist(type: AssetObject.self, id: assetID)
            }
            let groupObjects = Array(imageObject.groups)
            let assetBeforeUpdate = Asset(from: imageObject)
            let groupsBeforeUpdate = groupObjects.map{ Group(from: $0) }
            try realm.write {
                imageObject.imported = importStatus
            }
            let assetAfterUpdate = Asset(from: imageObject)
            return ((assetBeforeUpdate, assetAfterUpdate), changes(between: groupsBeforeUpdate, and: groupObjects))
        }
    }

    func deleteStatus(forAssetID assetID: UUID) throws -> Bool {
        try autoreleasepool {
            let realm = try Realm()
            guard let imageObject = realm.object(ofType: AssetObject.self, forPrimaryKey: assetID.string) else {
                throw DatabaseError.recordDoesNotExist(type: AssetObject.self, id: assetID)
            }
            return imageObject.deleted
        }
    }

    func save(deleteStatus: Bool, forAssetID assetID: UUID) throws -> ((Asset, Asset), [(Group, Group)]?) {
        try autoreleasepool {
            let realm = try Realm()
            guard let imageObject = realm.object(ofType: AssetObject.self, forPrimaryKey: assetID.string) else {
                throw DatabaseError.recordDoesNotExist(type: AssetObject.self, id: assetID)
            }
            let groupObjects = Array(imageObject.groups)
            let assetBeforeUpdate = Asset(from: imageObject)
            let groupsBeforeUpdate = groupObjects.map{ Group(from: $0) }
            try realm.write {
                imageObject.deleted = deleteStatus
            }
            let assetAfterUpdate = Asset(from: imageObject)
            return ((assetBeforeUpdate, assetAfterUpdate), changes(between: groupsBeforeUpdate, and: groupObjects))
        }
    }

    func remotePath(forAssetID assetID: UUID, atQuality quality: AssetManager.Quality) throws -> URL? {
        try autoreleasepool {
            let realm = try Realm()
            guard let imageObject = realm.object(ofType: AssetObject.self, forPrimaryKey: assetID.string) else {
                throw DatabaseError.recordDoesNotExist(type: AssetObject.self, id: assetID)
            }
            let physicalObject = imageObject.physicalAsset(for: quality)
            return URL(optionalString: physicalObject.remotePath)
        }
    }

    func save(remotePath: URL?, forAssetID assetID: UUID, atQuality quality: AssetManager.Quality) throws {
        try autoreleasepool {
            let realm = try Realm()
            guard let imageObject = realm.object(ofType: AssetObject.self, forPrimaryKey: assetID.string) else {
                throw DatabaseError.recordDoesNotExist(type: AssetObject.self, id: assetID)
            }
            try realm.write {
                let physicalObject = imageObject.physicalAsset(for: quality)
                physicalObject.remotePath = remotePath?.absoluteString
            }
        }
    }

    func pruneLocalIDs(forAssetIDs assetIDs: [UUID]) throws {
        try autoreleasepool {
            let realm = try Realm()
            let assetObjects: Results<AssetObject> = try query(assetIDs, from: realm)
            try realm.write {
                assetObjects.forEach{ $0.localIdentifier = nil }
            }
        }
    }

    func sync<T>(_ data: [UUID: [String: Any]], withAssetIDs assetIDs: T) throws -> ([Asset]?, [(Group, Group)]?) where T: Collection, T.Element == UUID {
        try autoreleasepool {
            let realm = try Realm()
            let imageObjects: Results<AssetObject> = try query(assetIDs, from: realm)
            let groupObjects = Array(Set(imageObjects.flatMap{ $0.groups }))
            let groupsBeforeUpdate = groupObjects.map{ Group(from: $0) }
            var updatedObjects = [AssetObject]()
            try realm.write {
                for imageObject in imageObjects {
                    guard let uuid = UUID(uuidString: imageObject.uuid), let data = data[uuid] else { assertionFailure(imageObject.uuid); continue }
                    if imageObject.sync(with: data) {
                        updatedObjects.append(imageObject)
                    }
                }
            }
            return (updatedObjects.isEmpty ? nil : updatedObjects.map{ Asset(from: $0) }, changes(between: groupsBeforeUpdate, and: groupObjects))
        }
    }

    func addLocalAssets<T>(_ assets: T) throws where T: Collection, T.Element == (Asset, String) {
        try autoreleasepool {
            let realm = try Realm()
            let assetObjects: [AssetObject] = assets.map {
                let object = AssetObject($0.0)
                object.localIdentifier = $0.1
                return object
            }
            try realm.write {
                realm.add(assetObjects)
            }
        }
    }

    func addRemoteAssets(from decryptedData: [UUID: [String: Any?]], serverData: [UUID: [String: Any]]) throws -> [Asset] {
        try autoreleasepool {
            let realm = try Realm()
            let imageObjects = decryptedData.compactMap{ AssetObject(id: $0.key, assetData: serverData[$0.key]!, decryptedAssetData: decryptedData[$0.key]!) }
            try realm.write {
                realm.add(imageObjects)
            }
            return imageObjects.map{ Asset(from: $0) }
        }
    }

    func remove<T>(assetIDs: T) throws -> [(Group, Group)]? where T: Collection, T.Element == UUID {
        try autoreleasepool {
            let realm = try Realm()
            let assetObjects: Results<AssetObject> = try query(assetIDs, from: realm)
            guard assetObjects.count == assetIDs.count else { throw DatabaseError.recordCountMismatch(expected: assetIDs.count, actual: assetObjects.count) }
            let groupObjects = Array(Set(assetObjects.flatMap{ $0.groups }))
            let groupsBeforeUpdate = groupObjects.map{ Group(from: $0) }
            try realm.write {
                delete(assetObjects, using: realm)
            }
            return changes(between: groupsBeforeUpdate, and: groupObjects)
        }
    }

    private func changes(between groupsBeforeUpdate: [Group], and groupObjects: [GroupObject]) -> [(Group, Group)]? {
        precondition(groupObjects.count == groupsBeforeUpdate.count)
        var groupChanges = [(Group, Group)]()
        for (index, oldGroup) in groupsBeforeUpdate.enumerated() {
            let newGroup = Group(from: groupObjects[index])
            if oldGroup != newGroup {
                groupChanges.append((oldGroup, newGroup))
            }
        }
        return groupChanges.isNotEmpty ? groupChanges : nil
    }
}
