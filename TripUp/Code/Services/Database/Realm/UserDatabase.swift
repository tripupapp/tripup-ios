//
//  UserDatabase.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 30/09/2019.
//  Copyright © 2019 Vinoth Ramiah. All rights reserved.
//

import Foundation
import RealmSwift

extension RealmDatabase: UserDatabase {
    var allUsers: [UUID: User] {
        autoreleasepool {
            guard let realm = try? Realm() else { return [UUID: User]() }
            let userObjects = realm.objects(UserObject.self)
            let users = userObjects.map{ User(from: $0) }
            return users.reduce(into: [UUID: User]()) {
                $0[$1.uuid] = $1
            }
        }
    }

    func lookup(_ id: UUID) -> User? {
        autoreleasepool {
            guard let realm = try? Realm(), let userObject = realm.object(ofType: UserObject.self, forPrimaryKey: id.string) else { return nil }
            return User(from: userObject)
        }
    }

    func add<T>(_ users: T) throws where T: Collection, T.Element == User {
        try autoreleasepool {
            let realm = try Realm()
            let userObjects = users.map{ UserObject($0) }
            try realm.write {
                realm.add(userObjects)
            }
        }
    }

    func remove<T>(userIDs: T) throws -> [Group] where T: Collection, T.Element == UUID {
        try autoreleasepool {
            let realm = try Realm()
            let userObjects: Results<UserObject> = try query(userIDs, from: realm)
            let groups = realm.objects(GroupObject.self).filter(NSPredicate(format: "ANY members IN %@", argumentArray: [userObjects])).map{ Group(from: $0) }
            try realm.write {
                realm.delete(userObjects)
            }
            return Array(groups)
        }
    }

    func update(_ localContact: Data?, forUserID userID: UUID) throws -> (User, [Group]) {
        try autoreleasepool {
            let realm = try Realm()
            guard let userObject = realm.object(ofType: UserObject.self, forPrimaryKey: userID.string) else { throw DatabaseError.recordDoesNotExist(type: UserObject.self, id: userID) }
            try realm.write {
                userObject.contact = localContact
            }
            let groups = realm.objects(GroupObject.self).filter(NSPredicate(format: "ANY members = %@", userObject)).map{ Group(from: $0) }
            return (User(from: userObject), Array(groups))
        }
    }
}
