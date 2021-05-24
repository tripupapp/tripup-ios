//
//  Album.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 16/10/2020.
//  Copyright © 2020 Vinoth Ramiah. All rights reserved.
//

import Foundation

struct Album: Hashable {
    let pics: [UUID: Asset]
    private let hiddenPics: [UUID: Asset]
    private let firstAssetID: UUID?
    private let lastAssetID: UUID?
    private let sharedAssetIDs: Set<UUID>

    init(pics: [UUID: Asset] = [UUID: Asset](), hiddenPics: [UUID: Asset] = [UUID: Asset](), firstAssetID: UUID? = nil, lastAssetID: UUID? = nil, sharedAssetIDs: Set<UUID> = Set<UUID>()) {
        self.pics = pics
        self.hiddenPics = hiddenPics
        self.firstAssetID = firstAssetID
        self.lastAssetID = lastAssetID
        self.sharedAssetIDs = sharedAssetIDs
    }

    var allAssets: [UUID: Asset] {
        return pics.merging(hiddenPics) { (current, _) in
            current
        }
    }
    var sharedAssets: [UUID: Asset] {
        sharedAssetIDs.reduce(into: [UUID: Asset]()) {
            $0[$1] = pics[$1]
        }
    }
    var firstAsset: Asset? {
        guard let id = firstAssetID else { return nil }
        return pics[id]
    }
    var lastAsset: Asset? {
        guard let id = lastAssetID else { return nil }
        return pics[id]
    }
    var startDate: Date {
        firstAsset?.creationDate ?? Date.distantFuture
    }
    var count: Int {
        return pics.count
    }
    var isEmpty: Bool {
        return pics.count == 0
    }
    var isNotEmpty: Bool {
        return !isEmpty
    }

    func contains(where condition: (Asset) -> Bool) -> Bool {
        return pics.values.contains(where: condition)
    }
}
