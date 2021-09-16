//
//  CollectionViewDataModel.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 19/08/2019.
//  Copyright © 2019 Vinoth Ramiah. All rights reserved.
//

import Foundation

struct CollectionViewDataModel {
    private var keysSorted: [Date]
    private var assetCollection: [Date: [Asset]]
    private var dateAscending: Bool

    subscript(index: Int) -> Asset {
        assert(Thread.isMainThread)
        return allItems[index]
    }

    var count: Int {
        assert(Thread.isMainThread)
        return assetCollection.values.flatMap{ $0 }.count
    }

    var numberOfSections: Int {
        assert(Thread.isMainThread)
        return assetCollection.count
    }

    var lastIndexPath: IndexPath? {
        assert(Thread.isMainThread)
        guard let lastDate = keysSorted.last else { return nil }
        let lastItemIndex = assetCollection[lastDate]!.endIndex - 1
        return IndexPath(item: lastItemIndex, section: keysSorted.endIndex - 1)
    }

    var allItems: [Asset] {
        assert(Thread.isMainThread)
        // assuming dictionary values (array) is already sorted correctly
        var assets = [Asset]()
        for key in keysSorted {
            assets += assetCollection[key]!
        }
        return assets
    }

    private var dateComparator: (Date, Date) -> Bool {
        assert(Thread.isMainThread)
        return dateAscending ? (<) : ((>))
    }

    init(assets: [UUID: Asset], dateAscending: Bool = true) {
        assert(Thread.isMainThread)
        self.dateAscending = dateAscending
        let assetsSorted = assets.values.sorted(by: .creationDate(ascending: true))
        self.assetCollection = Dictionary(grouping: assetsSorted){ Calendar.current.startOfDay(for: $0.creationDate ?? .distantPast) }
        self.keysSorted = assetCollection.keys.sorted(by: dateAscending ? (<) : ((>)))
    }

    func numberOfItems(inSection section: Int) -> Int {
        assert(Thread.isMainThread)
        let sectionKey = key(at: section)
        return assetCollection[sectionKey]!.count
    }

    func key(at indexPathSection: Int) -> Date {
        assert(Thread.isMainThread)
        return keysSorted[indexPathSection]
    }

    func item(at indexPath: IndexPath) -> Asset {
        assert(Thread.isMainThread)
        return items(at: [indexPath])[0]
    }

    func items(at indexPaths: [IndexPath], matchingPredicate predicate: ((Asset) -> Bool)? = nil) -> [Asset] {
        assert(Thread.isMainThread)
        var assets = [Asset]()
        for indexPath in indexPaths {
            guard indexPath.section < keysSorted.count else { assertionFailure("\(indexPath.section) >= \(keysSorted.count)"); continue }
            let key = keysSorted[indexPath.section]
            guard let itemsArray = assetCollection[key] else { assertionFailure("\(key)"); continue }
            guard indexPath.row < itemsArray.count else { assertionFailure("\(indexPath.row) >= \(itemsArray.count)"); continue }
            let asset = itemsArray[indexPath.row]   // assuming itemsArray is already sorted
            if predicate?(asset) ?? true {
                assets.append(asset)
            }
        }
        assert(predicate == nil ? indexPaths.count == assets.count : true)
        return assets
    }

    func indexPath(for asset: Asset) -> IndexPath {
        assert(Thread.isMainThread)
        return indexPaths(for: [asset])[0]
    }

    func indexPaths<T: Sequence>(for assets: T) -> [IndexPath] where T.Element == Asset {
        assert(Thread.isMainThread)
        return indexPaths(for: assets).map{ $0! }
    }

    func indexPaths<T: Sequence>(for assets: T) -> [IndexPath?] where T.Element == Asset {
        assert(Thread.isMainThread)
        var indexPaths = [IndexPath?]()
        for asset in assets {
            let key = Calendar.current.startOfDay(for: asset.creationDate ?? .distantPast)
            if let assetsForKey = assetCollection[key], let item = assetsForKey.firstIndex(of: asset), let section = keysSorted.firstIndex(of: key) {
                indexPaths.append(IndexPath(item: item, section: section))
            } else {
                indexPaths.append(nil)
            }
        }
        return indexPaths
    }

    func convertToIndex(_ indexPath: IndexPath) -> Int {
        assert(Thread.isMainThread)
        var count = 0
        for index in 0..<indexPath.section {
            count += assetCollection[keysSorted[index]]!.count
        }
        return count + indexPath.item
    }

    mutating func insert<T: Sequence>(_ assets: T) -> (IndexSet, [IndexPath]) where T.Element == Asset {
        assert(Thread.isMainThread)
        var newKeys = [Date]()
        var keysOfArraysToSort = [Date]()
        for asset in assets {
            let date = Calendar.current.startOfDay(for: asset.creationDate ?? .distantPast)
            if assetCollection[date]?.append(asset) != nil {
                keysOfArraysToSort.append(date)
            } else {
                assetCollection[date] = [asset]
                newKeys.append(date)
            }
        }

        if newKeys.isNotEmpty {
            keysSorted.append(contentsOf: newKeys)
            keysSorted.sort(by: dateComparator)
        }
        for key in keysOfArraysToSort {
            assetCollection[key]?.sort(by: .creationDate(ascending: true))
        }

        let insertedSections = newKeys.map{ keysSorted.firstIndex(of: $0)! }
        let insertedItemsIndexes = assets.map { asset -> IndexPath in
            let key = Calendar.current.startOfDay(for: asset.creationDate ?? .distantPast)
            let section = keysSorted.firstIndex(of: key)!
            let item = assetCollection[key]!.firstIndex(of: asset)!
            return IndexPath(item: item, section: section)
        }
        return (IndexSet(insertedSections), insertedItemsIndexes)
    }

    mutating func remove<T: Sequence>(_ assets: T) -> (IndexSet, [IndexPath]) where T.Element == Asset {
        assert(Thread.isMainThread)
        let oldKeysSorted = keysSorted
        let oldData = assetCollection
        var keysRemoved = [Date]()
        for asset in assets {
            let date = Calendar.current.startOfDay(for: asset.creationDate ?? .distantPast)
            guard var array = assetCollection[date], let index = array.firstIndex(of: asset) else { continue }
            array.remove(at: index)
            if array.isNotEmpty {
                assetCollection[date] = array
            } else {
                assetCollection[date] = nil
                keysRemoved.append(date)
            }
        }

        if keysRemoved.isNotEmpty {
            keysSorted = Set(keysSorted).subtracting(keysRemoved).sorted(by: dateComparator)
        }

        let deletedSections = keysRemoved.map{ oldKeysSorted.firstIndex(of: $0)! }
        let deletedItemIndexes = assets.compactMap { asset -> IndexPath? in
            let key = Calendar.current.startOfDay(for: asset.creationDate ?? .distantPast)
            guard let section = oldKeysSorted.firstIndex(of: key) else { return nil }
            guard let item = oldData[key]?.firstIndex(of: asset) else { return nil }
            return IndexPath(item: item, section: section)
        }
        return (IndexSet(deletedSections), deletedItemIndexes)
    }

    mutating func update(_ oldAsset: Asset, to newAsset: Asset) -> ([Int?], [IndexPath?]) {
        assert(Thread.isMainThread)
        let (removedSections, removedIndexPaths) = remove([oldAsset])
        let (insertedSections, insertedIndexPaths) = insert([newAsset])
        return ([removedSections.first, insertedSections.first], [removedIndexPaths.first, insertedIndexPaths.first])
    }

    mutating func reload(withData newData: [UUID: Asset], predicate: ((Asset) -> Bool)? = nil, dateAscending: Bool = true) -> (IndexSet, IndexSet, [[Int]], [IndexPath], [IndexPath], [[IndexPath]]) {
        assert(Thread.isMainThread)
        let currentSort = dateComparator
        let currentAssets = assetCollection

        self.dateAscending = dateAscending
        var assets = Array(newData.values)
        if let predicate = predicate {
            assets = assets.filter(predicate)
        }

        assets.sort(by: .creationDate(ascending: true))
        let newAssets = Dictionary(grouping: assets){ Calendar.current.startOfDay(for: $0.creationDate ?? .distantPast) }
        self.assetCollection = newAssets
        self.keysSorted = newAssets.keys.sorted(by: dateComparator)

        return calculateIndexPathChanges(from: currentAssets, with: currentSort, to: newAssets, with: dateComparator)
    }

    private func calculateIndexPathChanges(from oldData: [Date: [Asset]], with oldSort: (Date, Date) -> Bool, to newData: [Date: [Asset]], with newSort: (Date, Date) -> Bool) -> (IndexSet, IndexSet, [[Int]], [IndexPath], [IndexPath], [[IndexPath]]) {
        // section changes
        let oldKeys = oldData.keys.sorted(by: oldSort)
        let newKeys = newData.keys.sorted(by: newSort)

        let deletedKeys = Set(oldKeys).subtracting(newKeys)
        let deletedSectionIndexes = deletedKeys.map{ oldKeys.firstIndex(of: $0)! }

        let insertedKeys = Set(newKeys).subtracting(oldKeys)
        let insertedSectionIndexes = insertedKeys.map{ newKeys.firstIndex(of: $0)! }

//        let movedKeys = Set(newKeys).intersection(oldKeys)
//        let movedSectionIndexes = movedKeys.map{ [oldKeys.firstIndex(of: $0)!, newKeys.firstIndex(of: $0)!] }

        // item changes
        let oldValues = oldData.values.flatMap{ $0 }
        let newValues = newData.values.flatMap{ $0 }

        let deletedValues = Set(oldValues).subtracting(newValues)
        let deletedItemIndexes = deletedValues.map { asset -> IndexPath in
            let key = Calendar.current.startOfDay(for: asset.creationDate ?? .distantPast)
            let section = oldKeys.firstIndex(of: key)!
            let item = oldData[key]!.firstIndex(of: asset)!
            return IndexPath(item: item, section: section)
        }

        let insertedValues = Set(newValues).subtracting(oldValues)
        let insertedItemIndexes = insertedValues.map { asset -> IndexPath in
            let key = Calendar.current.startOfDay(for: asset.creationDate ?? .distantPast)
            let section = newKeys.firstIndex(of: key)!
            let item = newData[key]!.firstIndex(of: asset)!
            return IndexPath(item: item, section: section)
        }

        // TODO: the intersection of old and new values does not necessarily represent a "moved item" - optimisation would be to determine which items have *actually* changed position
        let movedValues = Set(newValues).intersection(oldValues)
        let movedItemIndexes = movedValues.map { asset -> [IndexPath] in
            let key = Calendar.current.startOfDay(for: asset.creationDate ?? .distantPast)
            let oldSection = oldKeys.firstIndex(of: key)!
            let oldItem = oldData[key]!.firstIndex(of: asset)!
            let newSection = newKeys.firstIndex(of: key)!
            let newItem = newData[key]!.firstIndex(of: asset)!
            return [IndexPath(item: oldItem, section: oldSection), IndexPath(item: newItem, section: newSection)]
        }

        return (IndexSet(deletedSectionIndexes), IndexSet(insertedSectionIndexes), [[Int]]() /*movedSectionIndexes*/, deletedItemIndexes, insertedItemIndexes, movedItemIndexes)
    }
}
