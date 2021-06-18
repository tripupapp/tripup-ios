//
//  RealmTripDatabase.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 24/09/2019.
//  Copyright © 2019 Vinoth Ramiah. All rights reserved.
//

import Foundation
import RealmSwift

class RealmDatabase {
    func query<T, U>(_ ids: T, from realm: Realm, exact: Bool = true) throws -> Results<U> where T: Collection, T.Element == UUID, U: Object {
        let objects = realm.objects(U.self).filter(NSPredicate(format: "uuid IN %@", ids.map{ $0.string }))
        if exact, objects.count != ids.count {
            throw DatabaseError.recordCountMismatch(expected: ids.count, actual: objects.count)
        }
        return objects
    }

    func delete<T: Sequence>(_ imageObjects: T, using realm: Realm) where T.Iterator.Element: AssetObject {
        assert(realm.isInWriteTransaction)
        var physicalObjects = [PhysicalAssetObject]()
        for imageObject in imageObjects {
            physicalObjects.append(imageObject.physicalAssetLow!)
            physicalObjects.append(imageObject.physicalAssetOriginal!)
        }
        realm.delete(physicalObjects)
        realm.delete(imageObjects)
    }
}

extension RealmDatabase: Database {
    func configure() {
        autoreleasepool {
            /*
                schemaVersion: Set the new schema version. This must be greater than the previously used
                version (if you've never set a schema version before, the version is 0).

                - 11 and lower are legacy builds (v1 on App Store, v0.1 tag on git)
                - 12 is first major re-release (v2 on App Store, v1.0 tag on git)
                - 13 is for video support (v2.1 on App Store, v1.1 tag on git)
            */
            var config = Realm.Configuration(schemaVersion: 13)
            if let realmFileURL = Realm.Configuration.defaultConfiguration.fileURL, let oldSchemaVersion = try? schemaVersionAtURL(realmFileURL), oldSchemaVersion <= 11 {
                // if data exists from a legacy version of TripUp, delete entire database file and start again
                config.deleteRealmIfMigrationNeeded = true
            } else {
                // migrationBlock: Set the block which will be called automatically when opening a Realm with
                // a schema version lower than the one set above
                config.migrationBlock = { migration, oldSchemaVersion in
                    if oldSchemaVersion < 13 {
                        migration.enumerateObjects(ofType: AssetObject.className()) { (_, newObject) in
                            newObject!["type"] = "photo"
                            newObject!["duration"] = nil
                        }
                    }
                }
            }

            // Tell Realm to use this new configuration object for the default Realm
            Realm.Configuration.defaultConfiguration = config
        }
    }

    func clear() {
        autoreleasepool {
            guard let realm = try? Realm() else { return }
            try! realm.write {
                realm.deleteAll()
            }
        }
    }
}
