//
//  Asset.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 20/07/2017.
//  Copyright © 2017 Vinoth Ramiah. All rights reserved.
//

import Foundation
import Photos

struct Asset: Hashable {
    let uuid: UUID
    let ownerID: UUID
    let creationDate: Date?
    let location: TULocation?
    let pixelSize: CGSize
    let imported: Bool

    var favourite: Bool = false
    var hidden: Bool = false
}

extension Asset {
    enum Comparison {
        case creationDate(ascending: Bool)
    }
}

extension Sequence where Iterator.Element == Asset {
    func sorted(by comparator: Asset.Comparison) -> [Asset] {
        switch comparator {
        case .creationDate(let ascending):
            let dateComparator: (Date, Date) -> Bool = ascending ? (<) : (>)
            let stringComparator: (String, String) -> Bool = ascending ? (<) : (>)
            return self.sorted { (asset1, asset2) -> Bool in
                if let asset1Date = asset1.creationDate, let asset2Date = asset2.creationDate, asset1Date != asset2Date {
                    return dateComparator(asset1Date, asset2Date)
                } else {
                    return stringComparator(asset1.uuid.string, asset2.uuid.string)
                }
            }
        }
    }
}

extension Array where Iterator.Element == Asset {
    mutating func sort(by comparator: Asset.Comparison) {
        switch comparator {
        case .creationDate(let ascending):
            let dateComparator: (Date, Date) -> Bool = ascending ? (<) : (>)
            let stringComparator: (String, String) -> Bool = ascending ? (<) : (>)
            self.sort { (asset1, asset2) -> Bool in
                if let asset1Date = asset1.creationDate, let asset2Date = asset2.creationDate, asset1Date != asset2Date {
                    return dateComparator(asset1Date, asset2Date)
                } else {
                    return stringComparator(asset1.uuid.string, asset2.uuid.string)
                }
            }
        }
    }
}

extension Asset {
    init(_ mutableAsset: AssetManager.MutableAsset) {
        self.uuid = mutableAsset.uuid
        self.ownerID = mutableAsset.ownerID
        self.creationDate = mutableAsset.creationDate
        self.location = mutableAsset.location
        self.pixelSize = mutableAsset.pixelSize
        self.imported = mutableAsset.imported
        self.hidden = mutableAsset.deleted
        self.favourite = false  // TODO
    }
}

extension Asset {
    init(from object: AssetObject) {
        self.uuid = UUID(uuidString: object.uuid)!
        self.ownerID = UUID(uuidString: object.ownerID)!
        self.creationDate = object.creationDate
        self.location = TULocation(from: object)
        self.pixelSize = CGSize(width: object.pixelWidth, height: object.pixelHeight)
        self.imported = object.imported
        self.favourite = object.favourite
        self.hidden = object.deleted
    }
}
