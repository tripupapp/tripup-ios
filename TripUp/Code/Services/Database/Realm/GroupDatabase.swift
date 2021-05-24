//
//  GroupDatabase.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 30/09/2019.
//  Copyright © 2019 Vinoth Ramiah. All rights reserved.
//

import Foundation
import RealmSwift

extension RealmDatabase: GroupDatabase {
    var allGroups: [UUID: Group] {
        autoreleasepool {
            guard let realm = try? Realm() else { return [UUID: Group]() }
            let groupObjects = realm.objects(GroupObject.self)
            let groups = groupObjects.map{ Group(from: $0) }
            return groups.reduce(into: [UUID: Group]()) {
                $0[$1.uuid] = $1
            }
        }
    }

    func lookup(_ id: UUID) -> Group? {
        autoreleasepool {
            guard let realm = try? Realm(), let groupObject = realm.object(ofType: GroupObject.self, forPrimaryKey: id.string) else { return nil }
            return Group(from: groupObject)
        }
    }

    func addGroup(_ group: Group) throws {
        try autoreleasepool {
            let realm = try Realm()
            let groupObject = GroupObject(group)
            let userObjects: Results<UserObject> = try query(group.members.map{ $0.uuid }, from: realm)
            try realm.write {
                realm.add(groupObject)
                groupObject.members.append(objectsIn: userObjects)
            }
        }
    }

    func removeGroup(_ group: Group) throws {
        try autoreleasepool {
            let realm = try Realm()
            guard let groupObject = realm.object(ofType: GroupObject.self, forPrimaryKey: group.uuid.string) else { throw DatabaseError.recordDoesNotExist(type: GroupObject.self, id: group.uuid) }
            try realm.write {
                realm.delete(groupObject)
            }
        }
    }

    func updateGroup(id: UUID, assetIDs: [UUID], sharedAssetIDs: [UUID]) throws -> Group {
        try autoreleasepool {
            let realm = try Realm()
            guard let groupObject = realm.object(ofType: GroupObject.self, forPrimaryKey: id.string) else { throw DatabaseError.recordDoesNotExist(type: GroupObject.self, id: id) }
            let assetObjects = realm.objects(AssetObject.self).filter(NSPredicate(format: "uuid IN %@", assetIDs.map{ $0.string }))
            guard assetObjects.count == assetIDs.count else { throw DatabaseError.recordCountMismatch(expected: assetIDs.count, actual: assetObjects.count) }
            let sharedAssetObjects = realm.objects(AssetObject.self).filter(NSPredicate(format: "uuid IN %@", sharedAssetIDs.map{ $0.string }))
            guard sharedAssetObjects.count == sharedAssetIDs.count else { throw DatabaseError.recordCountMismatch(expected: assetIDs.count, actual: assetObjects.count) }
            try realm.write {
                groupObject.album.removeAll()
                groupObject.album.append(objectsIn: assetObjects)
                groupObject.sharedAlbum.removeAll()
                groupObject.sharedAlbum.append(objectsIn: sharedAssetObjects)
            }
            return Group(from: groupObject)
        }
    }

    func addUsers<T>(withIDs userIDs: T, toGroupID groupID: UUID) throws -> Group where T: Collection, T.Element == UUID {
        try autoreleasepool {
            let realm = try Realm()
            guard let groupObject = realm.object(ofType: GroupObject.self, forPrimaryKey: groupID.string) else { throw DatabaseError.recordDoesNotExist(type: GroupObject.self, id: groupID) }
            let userObjects: Results<UserObject> = try query(userIDs, from: realm)
            let newUserObjects = userObjects.filter(NSPredicate(format: "NOT (%K IN %@)", #keyPath(UserObject.uuid), groupObject.members.map{ $0.uuid }))
            try realm.write {
                groupObject.members.append(objectsIn: newUserObjects)
            }
            return Group(from: groupObject)
        }
    }

    func removeUsers<T>(withIDs userIDs: T, fromGroupID groupID: UUID) throws -> Group where T: Collection, T.Element == UUID {
        try autoreleasepool {
            let realm = try Realm()
            guard let groupObject = realm.object(ofType: GroupObject.self, forPrimaryKey: groupID.string) else { throw DatabaseError.recordDoesNotExist(type: GroupObject.self, id: groupID) }
            let result = Array(groupObject.members.filter(NSPredicate(format: "NOT (%K IN %@)", #keyPath(UserObject.uuid), userIDs.map{ $0.string })))
            try realm.write {
                groupObject.members.removeAll()
                groupObject.members.append(objectsIn: result)
            }
            return Group(from: groupObject)
        }
    }

    func addAssets<T>(ids assetIDs: T, toGroupID groupID: UUID) throws -> Group where T: Collection, T.Element == UUID {
        try autoreleasepool {
            let realm = try Realm()
            let imageObjects: Results<AssetObject> = try query(assetIDs, from: realm)
            guard imageObjects.count == assetIDs.count else { throw DatabaseError.recordCountMismatch(expected: assetIDs.count, actual: imageObjects.count) }
            guard let groupObject = realm.object(ofType: GroupObject.self, forPrimaryKey: groupID.string) else { throw DatabaseError.recordDoesNotExist(type: GroupObject.self, id: groupID) }
            let assetsToAdd = imageObjects.filter(NSPredicate(format: "NOT (%K IN %@)", #keyPath(AssetObject.uuid), groupObject.album.map{ $0.uuid }))
            try realm.write {
                groupObject.album.append(objectsIn: assetsToAdd)
            }
            return Group(from: groupObject)
        }
    }

    func removeAssets<T>(ids assetIDs: T, fromGroupID groupID: UUID) throws -> Group where T: Collection, T.Element == UUID {
        try autoreleasepool {
            let realm = try Realm()
            guard let groupObject: GroupObject = realm.object(ofType: GroupObject.self, forPrimaryKey: groupID.string) else { throw DatabaseError.recordDoesNotExist(type: GroupObject.self, id: groupID) }
            let imageObjectsToKeep = Array(groupObject.album.filter(NSPredicate(format: "NOT (%K IN %@)", #keyPath(AssetObject.uuid), assetIDs.map{ $0.string }))) // wrap in Array as the subsequent removeAll function empties the result
            let sharedImageObjectsToKeep = Array(groupObject.sharedAlbum.filter(NSPredicate(format: "NOT (%K IN %@)", #keyPath(AssetObject.uuid), assetIDs.map{ $0.string })))
            try realm.write {
                groupObject.album.removeAll()
                groupObject.album.append(objectsIn: imageObjectsToKeep)
                groupObject.sharedAlbum.removeAll()
                groupObject.sharedAlbum.append(objectsIn: sharedImageObjectsToKeep)
            }
            return Group(from: groupObject)
        }
    }

    func shareAssets<T>(ids assetIDs: T, withGroupID groupID: UUID) throws -> Group where T: Collection, T.Element == UUID {
        try autoreleasepool {
            let realm = try Realm()
            guard let groupObject = realm.object(ofType: GroupObject.self, forPrimaryKey: groupID.string) else { throw DatabaseError.recordDoesNotExist(type: GroupObject.self, id: groupID) }
            let imageObjectsToShare = groupObject.album.filter(NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "%K IN %@", #keyPath(AssetObject.uuid), assetIDs.map{ $0.string }),
                NSPredicate(format: "NOT (%K IN %@)", #keyPath(AssetObject.uuid), groupObject.sharedAlbum.map{ $0.uuid })
            ]))
            try realm.write {
                groupObject.sharedAlbum.append(objectsIn: imageObjectsToShare)
            }
            return Group(from: groupObject)
        }
    }

    func unshareAssets<T>(ids assetIDs: T, fromGroupID groupID: UUID) throws -> Group where T: Collection, T.Element == UUID {
        try autoreleasepool {
            let realm = try Realm()
            guard let groupObject = realm.object(ofType: GroupObject.self, forPrimaryKey: groupID.string) else { throw DatabaseError.recordDoesNotExist(type: GroupObject.self, id: groupID) }
            let imageObjectsToKeepSharing = Array(groupObject.sharedAlbum.filter(NSPredicate(format: "NOT (%K IN %@)", #keyPath(AssetObject.uuid), assetIDs.map{ $0.string })))
            try realm.write {
                groupObject.sharedAlbum.removeAll()
                groupObject.sharedAlbum.append(objectsIn: imageObjectsToKeepSharing)
            }
            return Group(from: groupObject)
        }
    }
}
