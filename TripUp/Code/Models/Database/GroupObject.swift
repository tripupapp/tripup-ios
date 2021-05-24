//
//  GroupObject.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 28/09/2019.
//  Copyright © 2019 Vinoth Ramiah. All rights reserved.
//

import Foundation
import RealmSwift

final class GroupObject: Object {
    @objc dynamic var uuid: String = ""
    @objc dynamic var name: String = ""
    @objc dynamic var fingerprint: String = ""
    let members = List<UserObject>()
    let album = List<AssetObject>()
    let sharedAlbum = List<AssetObject>()

    override static func primaryKey() -> String? {
        return "uuid"
    }

    convenience init(_ group: Group) {
        self.init()
        self.uuid = group.uuid.string
        self.name = group.name
        self.fingerprint = group.fingerprint
    }
}

extension Group {
    init?(from object: GroupObject?) {
        guard let object = object else { return nil }
        self.init(from: object)
    }

    init(from object: GroupObject) {
        let allAssets = object.album.map{ Asset(from: $0) }
        let assets = allAssets.filter{ !$0.hidden }.reduce(into: [UUID: Asset]()) {
            $0[$1.uuid] = $1
        }

        let sortedAssets = assets.values.sorted(by: .creationDate(ascending: true))
        let hiddenAssets = Set(allAssets).subtracting(assets.values).reduce(into: [UUID: Asset]()) {
            $0[$1.uuid] = $1
        }
        let album = Album(pics: assets, hiddenPics: hiddenAssets, firstAssetID: sortedAssets.first?.uuid, lastAssetID: sortedAssets.last?.uuid, sharedAssetIDs: Set(object.sharedAlbum.compactMap{ UUID(uuidString: $0.uuid) }))

        self.uuid = UUID(uuidString: object.uuid)!
        self.name = object.name
        self.fingerprint = object.fingerprint
        self.members = Set(object.members.map{ User(from: $0) })
        self.album = album
    }
}
