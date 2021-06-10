//
//  AssetObject.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 28/09/2019.
//  Copyright © 2019 Vinoth Ramiah. All rights reserved.
//

import Foundation
import RealmSwift

@objcMembers final class AssetObject: Object {
    dynamic var uuid: String = ""
    dynamic var type: String = ""
    dynamic var ownerID: String = ""
    dynamic var creationDate: Date? = nil
    let latitude = RealmOptional<Double>()
    let longitude = RealmOptional<Double>()
    let altitude = RealmOptional<Double>()
    dynamic var pixelWidth: Int = 0
    dynamic var pixelHeight: Int = 0
    dynamic var fingerprint: String? = nil
    dynamic var originalUTI: String? = nil
    dynamic var localIdentifier: String? = nil
    dynamic var totalSize: Int64 = 0
    dynamic var md5: Data? = nil
    dynamic var imported: Bool = false
    dynamic var deleted: Bool = false

    dynamic var physicalAssetOriginal: PhysicalAssetObject? = PhysicalAssetObject()
    dynamic var physicalAssetLow: PhysicalAssetObject? = PhysicalAssetObject()

    let groups = LinkingObjects(fromType: GroupObject.self, property: "album")

    var favourite: Bool {
        return false
//        let state = ImageAsset.State(rawValue: regionsFavourite)!
//        return (state == .favourite && regionsFavouriteError == 0) || state == .favouriting || (state == .notFavourite && regionsFavouriteError > 0)
    }

    override static func primaryKey() -> String? {
        return "uuid"
    }

    convenience init(_ asset: Asset) {
        self.init()
        self.uuid = asset.uuid.string
        self.type = asset.type.rawValue
        self.ownerID = asset.ownerID.string
        self.creationDate = asset.creationDate
        self.latitude.value = asset.location?.latitude
        self.longitude.value = asset.location?.longitude
        self.altitude.value = asset.location?.altitude
        self.pixelWidth = Int(asset.pixelSize.width)
        self.pixelHeight = Int(asset.pixelSize.height)
        self.imported = asset.imported
        self.deleted = asset.hidden
//        self.regionsFavourite = asset.favourite ? ImageAsset.State.favourite.rawValue : ImageAsset.State.notFavourite.rawValue
    }

    func physicalAsset(for quality: AssetManager.Quality) -> PhysicalAssetObject {
        switch quality {
        case .original:
            return physicalAssetOriginal!
        case .low:
            return physicalAssetLow!
        }
    }
}

extension AssetObject {
    convenience init?(id: UUID, assetData: [String: Any], decryptedAssetData: [String: Any?]) {
        // server data response check
        guard let type = assetData["type"] as? String, let ownerIDstring = assetData["ownerid"] as? String, let pixelWidth = assetData["pixelwidth"] as? Int, let pixelHeight = assetData["pixelheight"] as? Int, let remotePathLow = assetData["remotepath"] as? String else {
            assertionFailure("invalid JSON response – assetID: \(id.string)")
            return nil
        }
        // valid data check
        guard AssetType(rawValue: type) != nil, UUID(uuidString: ownerIDstring) != nil, pixelWidth != 0, pixelHeight != 0, URL(string: remotePathLow) != nil else {
            assertionFailure("invalid server data – assetID: \(id.string)")
            return nil
        }
        // check decrypted contents
        guard let assetKey = decryptedAssetData["key"] as? CryptoPrivateKey else {
            assertionFailure("no asset key – assetID: \(id.string)")
            return nil
        }
        guard let md5 = decryptedAssetData["md5"] as? Data else {
            assertionFailure("no md5 data – assetID: \(id.string)")
            return nil
        }
        let creationDate = decryptedAssetData["createdate"] as? Date
        let location = decryptedAssetData["location"] as? TULocation

        self.init()
        self.uuid = id.string
        self.type = type
        self.ownerID = ownerIDstring
        self.creationDate = creationDate
        self.latitude.value = location?.latitude
        self.longitude.value = location?.longitude
        self.altitude.value = location?.altitude
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.fingerprint = assetKey.fingerprint
        self.originalUTI = assetData["originaluti"] as? String
        self.totalSize = assetData["totalsize"] as? Int64 ?? 0
        self.md5 = md5
        self.imported = true
        self.deleted = false

        self.physicalAssetLow?.remotePath = remotePathLow
        self.physicalAssetOriginal?.remotePath = assetData["remotepathorig"] as? String
        // TODO
//        favourite: assetData["favourite"] as! Bool,
    }
}

extension AssetObject {
    func sync(with assetData: [String: Any]) -> Bool {
        var changed = false

        // file size
        if let totalFilesize = assetData["totalsize"] as? Int64, totalFilesize != totalSize {
            totalSize = totalFilesize
            changed = true
        }

        // remote - original url
        if let remotePathOriginal = assetData["remotepathorig"] as? String, physicalAssetOriginal?.remotePath == nil {
            guard URL(string: remotePathOriginal) != nil else {
                assertionFailure("remotepathorig not a valid URL – assetID: \(uuid), remotePathOrig: \(remotePathOriginal)")
                return changed
            }
            physicalAssetOriginal?.remotePath = remotePathOriginal
            changed = true
        }

//        // favourite state
//        let serverStateFavourite = assetData["favourite"] as! Bool
//        if serverStateFavourite && asset.regions.favourite.currentStateSynced == .notFavourite {
//            imageAssetMachine.process(event: .favourited(true), for: asset)
//        } else if !serverStateFavourite && asset.regions.favourite.currentStateSynced == .favourite {
//            imageAssetMachine.process(event: .favourited(false), for: asset)
//        }

        return changed
    }
}

extension TULocation {
    init?(from object: AssetObject) {
        guard let latitude = object.latitude.value, let longitude = object.longitude.value, let altitude = object.altitude.value else { return nil }
        self.init(latitude: latitude, longitude: longitude, altitude: altitude)
    }
}

@objcMembers class PhysicalAssetObject: Object {
    dynamic var remotePath: String? = nil
}
