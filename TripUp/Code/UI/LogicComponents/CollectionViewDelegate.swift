//
//  CollectionViewDelegate.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 16/09/2021.
//  Copyright © 2021 Vinoth Ramiah. All rights reserved.
//

import Foundation
import UIKit

import TripUpViews

class CollectionViewDelegate: NSObject {
    let itemsPerRow: CGFloat = 4.0

    var collectionViewIsEmpty: Bool {
        return dataModel.count == 0
    }

    var cellConfiguration: ((_ cell: CollectionViewCell, _ asset: Asset) -> Void)?
    var isSelectable: ((_ asset: Asset) -> Bool)?
    var onSelection: ((_ collectionView: UICollectionView, _ dataModel: CollectionViewDataModel, _ selectedIndexPath: IndexPath) -> Void)?
    var onDeselection: ((_ collectionView: UICollectionView, _ dataModel: CollectionViewDataModel, _ deselectedIndexPath: IndexPath) -> Void)?
    var onCollectionViewUpdate: Closure?

    private let cellReuseIdentifier: String
    private let sectionHeaderReuseIdentifier = "CollectionViewSectionHeader"
    private let sectionFooterReuseIdentifier = "CollectionViewSectionFooter"
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd MMM yyyy, E"
        return formatter
    }()
    private let cellPadding: CGFloat = 1.0
    private let assetDataRequester: AssetDataRequester?
    private var dataModel: CollectionViewDataModel
    private let cache = NSCache<NSUUID, UIImage>()

    init(assetDataRequester: AssetDataRequester?, dateAscending: Bool = true, cellReuseIdentifier: String = "CollectionViewCell") {
        self.assetDataRequester = assetDataRequester
        self.dataModel = CollectionViewDataModel(assets: [UUID : Asset](), dateAscending: dateAscending)
        self.cache.countLimit = 200
        self.cellReuseIdentifier = cellReuseIdentifier
        super.init()
    }

    func insertPreliminaryData<T>(assets: T) where T: Sequence, T.Element == Asset {
        _ = dataModel.insert(assets)
    }

    func indexPath(forIndex index: Int) -> IndexPath {
        let asset = dataModel[index]
        return dataModel.indexPath(for: asset)
    }

    func indexPaths(for assets: [Asset]) -> [IndexPath] {
        return dataModel.indexPaths(for: assets)
    }

    func items(at indexPaths: [IndexPath]) -> [Asset] {
        return dataModel.items(at: indexPaths)
    }

    private func cellSize(for collectionView: UICollectionView) -> CGSize {
        let paddingSpace = cellPadding * (itemsPerRow - 1)
        let availableWidth = collectionView.frame.width - paddingSpace
        let widthPerItem = availableWidth / itemsPerRow
        return CGSize(width: widthPerItem, height: widthPerItem)
    }
}

extension CollectionViewDelegate {
    func insert(_ assets: Set<Asset>, into collectionView: UICollectionView) {
        let (newSections, newItems) = dataModel.insert(assets)
        batchUpdate(collectionView, deletedSections: nil, newSections: newSections, movedSection: nil, deletedItems: nil, newItems: newItems, movedItem: nil)
    }

    func delete(_ assets: Set<Asset>, from collectionView: UICollectionView) {
        let (deletedSections, deletedItems) = dataModel.remove(assets)
        batchUpdate(collectionView, deletedSections: deletedSections, newSections: nil, movedSection: nil, deletedItems: deletedItems, newItems: nil, movedItem: nil)
    }

    func update(_ asset: Asset, with newAsset: Asset, in collectionView: UICollectionView) {
        let (movedSection, movedItem) = dataModel.update(asset, to: newAsset)
        batchUpdate(collectionView, deletedSections: nil, newSections: nil, movedSection: movedSection, deletedItems: nil, newItems: nil, movedItem: movedItem)
    }

    private func batchUpdate(_ collectionView: UICollectionView, deletedSections: IndexSet?, newSections: IndexSet?, movedSection: [Int?]?, deletedItems: [IndexPath]?, newItems: [IndexPath]?, movedItem: [IndexPath?]?) {
        var itemVisibleBeforeUpdate = false
        if let previousIndexPath = movedItem?[0], collectionView.indexPathsForVisibleItems.contains(previousIndexPath) {
            itemVisibleBeforeUpdate = true
        }
        collectionView.performBatchUpdates({
            if let deletedItems = deletedItems, deletedItems.isNotEmpty {
                collectionView.deleteItems(at: deletedItems)
            }
            if let deletedSections = deletedSections, deletedSections.isNotEmpty {
                collectionView.deleteSections(deletedSections)
            }
            if let newSections = newSections, newSections.isNotEmpty {
                collectionView.insertSections(newSections)
            }
            if let newItems = newItems, newItems.isNotEmpty {
                collectionView.insertItems(at: newItems)
            }
            if let movedSection = movedSection, let newSection = movedSection[1] {
                if let oldSection = movedSection[0] {
                    collectionView.moveSection(oldSection, toSection: newSection)
                } else {
                    collectionView.insertSections(IndexSet([newSection]))
                }
            }
            if let movedItem = movedItem, let newIndexPath = movedItem[1], newIndexPath != movedItem[0] {
                if let oldIndexPath = movedItem[0] {
                    collectionView.moveItem(at: oldIndexPath, to: newIndexPath)
                } else {
                    collectionView.insertItems(at: [newIndexPath])
                }
            }
        }, completion: { [weak self] success in
            guard success else { return }   // required as collectionView updates can be interrupted mid-way, causing scrollToItem to force a reloadData, causing a crash in the data model due to index being out of bounds
            if itemVisibleBeforeUpdate, let newIndexPath = movedItem?[1], collectionView.indexPathsForVisibleItems.contains(newIndexPath) {
                collectionView.reloadItems(at: [newIndexPath])
            }
            self?.onCollectionViewUpdate?()
        })
    }
}

extension CollectionViewDelegate: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        if let isSelectable = isSelectable {
            let asset = dataModel.item(at: indexPath)
            return isSelectable(asset)
        }
        return true
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        onSelection?(collectionView, dataModel, indexPath)
    }

    func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        onDeselection?(collectionView, dataModel, indexPath)
    }
}

extension CollectionViewDelegate: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        return cellSize(for: collectionView)
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        return cellPadding
    }
}

extension CollectionViewDelegate: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return dataModel.numberOfItems(inSection: section)
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: cellReuseIdentifier, for: indexPath) as! CollectionViewCell

        let asset = dataModel.item(at: indexPath)
        cell.assetID = asset.uuid
        cell.durationLabel.text = asset.duration?.formattedString
        cell.imageView.image = nil
        cell.imageView.contentMode = .scaleAspectFill
        if let selectedIndexPaths = collectionView.indexPathsForSelectedItems, Set(selectedIndexPaths).contains(indexPath) {
            cell.select()
        } else {
            cell.deselect()
        }

        cellConfiguration?(cell, asset)
        cell.topGradient.isHidden = cell.topIconsHidden
        cell.bottomGradient.isHidden = cell.bottomIconsHidden
        cell.activityIndicator.startAnimating()

        if let image = cache.object(forKey: asset.uuid as NSUUID) {
            cell.imageView.image = image
            cell.activityIndicator.stopAnimating()
        } else {
            let imageViewSize = cell.imageView.bounds.size
            let widthRatio = imageViewSize.width / asset.pixelSize.width
            let heightRatio = imageViewSize.height / asset.pixelSize.height
            let ratio = asset.pixelSize.width > asset.pixelSize.height ? heightRatio : widthRatio
            let targetSize = CGSize(width: asset.pixelSize.width * ratio, height: asset.pixelSize.height * ratio)
            assetDataRequester?.requestImage(for: asset, format: .lowQuality(targetSize, UIScreen.main.scale)) { [weak self] (image, resultInfo) in
                guard cell.assetID == asset.uuid, let resultInfo = resultInfo else { return }
                if resultInfo.final {
                    if let image = image {
                        cell.imageView.image = image
                        if let cache = self?.cache, cache.object(forKey: asset.uuid as NSUUID) == nil {
                            cache.setObject(image, forKey: asset.uuid as NSUUID)
                        }
                    }
                } else if cell.imageView.image == nil {
                    cell.imageView.image = image
                }
                cell.activityIndicator.stopAnimating()
            }
        }

        return cell
    }

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return dataModel.numberOfSections
    }

    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        switch kind {
        case UICollectionView.elementKindSectionHeader:
            let sectionKey = dataModel.key(at: indexPath.section)
            if let headerView = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: sectionHeaderReuseIdentifier, for: indexPath) as? CollectionViewSectionHeader {
                headerView.day.text = dateFormatter.string(from: sectionKey)
                return headerView
            }
        case UICollectionView.elementKindSectionFooter:
            if let footerView = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: sectionFooterReuseIdentifier, for: indexPath) as? CollectionViewSectionFooter {
                return footerView
            }
        default:
            assertionFailure("viewForSupplementaryElementOfKind value: \(kind) is invalid")
        }
        return UICollectionReusableView()
    }
}

extension CollectionViewDelegate: UICollectionViewDataSourcePrefetching {
    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        let assets = dataModel.items(at: indexPaths)
        let imageViewSize = cellSize(for: collectionView)
        for asset in assets {
            guard cache.object(forKey: asset.uuid as NSUUID) == nil else { continue }
            let widthRatio = imageViewSize.width / asset.pixelSize.width
            let heightRatio = imageViewSize.height / asset.pixelSize.height
            let ratio = asset.pixelSize.width > asset.pixelSize.height ? heightRatio : widthRatio
            let targetSize = CGSize(width: asset.pixelSize.width * ratio, height: asset.pixelSize.height * ratio)
            assetDataRequester?.requestImage(for: asset, format: .lowQuality(targetSize, UIScreen.main.scale)) { [weak self] (image, resultInfo) in
                guard let self = self else { return }
                guard let image = image, let resultInfo = resultInfo, resultInfo.final, self.cache.object(forKey: asset.uuid as NSUUID) == nil else { return }
                self.cache.setObject(image, forKey: asset.uuid as NSUUID)
            }
        }
    }
}


class CollectionViewSectionHeader: UICollectionReusableView {
    @IBOutlet var day: UILabel!
}

class CollectionViewSectionFooter: UICollectionReusableView {}
