//
//  PhotoViewDelegate.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 21/08/2019.
//  Copyright © 2019 Vinoth Ramiah. All rights reserved.
//

import Foundation
import UIKit

class PhotoViewDelegate: NSObject {
    var isShared: ((_ asset: Asset) -> Bool)?
    var onSelection: ((_ collectionView: UICollectionView, _ dataModel: PhotoViewDataModel, _ selectedIndexPath: IndexPath) -> Void)?

    private let headerReuseIdentifier = "AssetSectionHeader"
    private let footerReuseIdentifier = "AssetSectionFooter"
    private let cellPadding: CGFloat = 1.0
    private let itemsPerRow: CGFloat = 4.0
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return formatter
    }()

    private let primaryUserID: UUID
    private let assetDataRequester: AssetDataRequester?
    private var dataModel: PhotoViewDataModel
    private let cache = NSCache<NSUUID, UIImage>()

    init(primaryUserID: UUID, assets: [UUID: Asset], assetDataRequester: AssetDataRequester?) {
        self.primaryUserID = primaryUserID
        self.assetDataRequester = assetDataRequester
        self.dataModel = PhotoViewDataModel(assets: assets)
        self.cache.countLimit = 100
    }

    func indexPath(forIndex index: Int) -> IndexPath {
        let asset = dataModel[index]
        return dataModel.indexPath(for: asset)
    }

    func items(at indexPaths: [IndexPath]) -> [Asset] {
        return dataModel.items(at: indexPaths)
    }

    func indexPaths(for assets: [Asset]) -> [IndexPath] {
        return dataModel.indexPaths(for: assets)
    }

    func swipeThresholdActivation(for collectionView: UICollectionView) -> CGFloat {
        let viewWidth = collectionView.frame.width
        let cellWidth = viewWidth / itemsPerRow
        return cellWidth / 4
    }

    private func cellSize(for collectionView: UICollectionView) -> CGSize {
        let paddingSpace = cellPadding * (itemsPerRow - 1)
        let availableWidth = collectionView.frame.width - paddingSpace
        let widthPerItem = availableWidth / itemsPerRow
        return CGSize(width: widthPerItem, height: widthPerItem)
    }
}

extension PhotoViewDelegate {
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
        }, completion: { _ in
            if itemVisibleBeforeUpdate, let newIndexPath = movedItem?[1], collectionView.indexPathsForVisibleItems.contains(newIndexPath) {
                collectionView.reloadItems(at: [newIndexPath])
            }
            UIView.animate(withDuration: 0.25) {
                collectionView.alpha = self.dataModel.count == 0 ? 0 : 1
            }
        })
    }
}

extension PhotoViewDelegate: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        onSelection?(collectionView, dataModel, indexPath)
    }
}

extension PhotoViewDelegate: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return dataModel.numberOfItems(inSection: section)
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: PhotoViewCell.reuseIdentifier, for: indexPath) as! PhotoViewCell
        let asset = dataModel.item(at: indexPath)

        cell.assetID = asset.uuid
        cell.imageView.image = nil
        cell.imageView.contentMode = .scaleAspectFill
        cell.activityIndicator.startAnimating()

        let shared = isShared?(asset) ?? false
        if #available(iOS 13.0, *), let image = UIImage(systemName: "eye") {
            cell.shareIcon.image = image
        }
        cell.durationLabel.text = asset.duration?.formattedString
        cell.shareIcon.isHidden = !shared
        cell.topGradient.isHidden = cell.topIconsHidden
        cell.bottomGradient.isHidden = cell.bottomIconsHidden
        if asset.ownerID == primaryUserID {
            if #available(iOS 13.0, *) {
                cell.shareActionIcon.image = UIImage(systemName: "eye")
                cell.unshareActionIcon.image = UIImage(systemName: "eye.slash")
            }
            cell.shareActionIconConstraint.isZoomed = shared
            cell.unshareActionIconConstraint.isZoomed = !shared
        } else {
            if #available(iOS 13.0, *) {
                cell.shareActionIcon.image = UIImage(systemName: "lock.circle")
                cell.unshareActionIcon.image = UIImage(systemName: "lock.circle")
            } else {
                cell.shareActionIcon.image = UIImage(named: "lock-closed-outline")
                cell.unshareActionIcon.image = UIImage(named: "lock-closed-outline")
            }
            cell.shareActionIconConstraint.isZoomed = true
            cell.unshareActionIconConstraint.isZoomed = true
        }
        cell.assetContents.isHidden = false // set to hidden in storyboard, but why?

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
            let headerView = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: headerReuseIdentifier, for: indexPath) as! PhotoViewSectionHeader
            headerView.day.text = dateFormatter.string(from: sectionKey)
            return headerView
        case UICollectionView.elementKindSectionFooter:
            let footerView = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: footerReuseIdentifier, for: indexPath) as! PhotoViewSectionFooter
            return footerView
        default:
            fatalError("viewForSupplementaryElementOfKind value: \(kind) is invalid")
        }
    }
}

//extension PhotoViewDelegate: UICollectionViewDataSourcePrefetching {
//    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
//        guard !gridMode else { return }
//        let assets = dataModel.items(at: indexPaths)
//        for asset in assets {
//            guard resizedCache.object(forKey: asset.uuid as NSUUID) == nil else { continue }
//            let size = cellSize(for: asset)
//            let scale = collectionView.traitCollection.displayScale
////            assetDataRequester.requestImage(for: asset, format: .opportunistic(size, scale)) { [weak self] (image, resultInfo) in
////                assert(Thread.isMainThread)
////                guard let self = self, let image = image else { return }
////                if let resultInfo = resultInfo, resultInfo.expensive {
////                    self.resizedCache.setObject(image, forKey: asset.uuid as NSUUID)
////                }
////            }
//        }
//    }
//}

extension PhotoViewDelegate: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        return cellSize(for: collectionView)
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        return cellPadding
    }
}

class PhotoViewSectionHeader: UICollectionReusableView {
    static let reuseIdentifier = "AssetSectionHeader"

    @IBOutlet var day: UILabel!
}

class PhotoViewSectionFooter: UICollectionReusableView {
    static let reuseIdentifier = "AssetSectionFooter"
}
