//
//  TripsView.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 24/03/2018.
//  Copyright © 2018 Vinoth Ramiah. All rights reserved.
//

import Foundation
import UIKit

import TripUpViews

class AlbumsVC: UIViewController {
    @IBOutlet var collectionView: UICollectionView!
    @IBOutlet var cloudProgressSyncView: CloudProgressSync!

    private weak var networkController: NetworkMonitorController?
    private var collectionViewDelegate: CollectionViewDelegate!
    private var groupManager: GroupManager?
    private var dependencyInjector: DependencyInjector?

    func initialise(groupManager: GroupManager?, groupObserverRegister: GroupObserverRegister?, assetManager: AssetManager?, networkController: NetworkMonitorController?, dependencyInjector: DependencyInjector?) {
        self.groupManager = groupManager
        self.networkController = networkController
        self.dependencyInjector = dependencyInjector

        let groups = groupManager?.allGroups.values.sorted(by: .startDate(ascending: false)) ?? [Group]()
        collectionViewDelegate = CollectionViewDelegate(groups: groups, assetDataRequester: assetManager)

        groupObserverRegister?.addObserver(self)
        assetManager?.syncTracker.addObserver(self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let refreshControl = UIRefreshControl()
        collectionView.refreshControl = refreshControl
        refreshControl.addTarget(self, action: #selector(networkReload(_:)), for: .valueChanged)

        collectionView.alpha = (groupManager?.allGroups.isEmpty ?? true) ? 0 : 1
        collectionView.delegate = collectionViewDelegate
        collectionView.dataSource = collectionViewDelegate
//        collectionView.prefetchDataSource = collectionViewDelegate
        collectionViewDelegate.onSelection = { [unowned self] (group: Group) in
            let photoVC = UIStoryboard(name: "Photo", bundle: nil).instantiateInitialViewController() as! PhotoView
            self.dependencyInjector?.initialise(photoView: photoVC)
            photoVC.group = group
            self.navigationController?.pushViewController(photoVC, animated: true)
        }
        collectionViewDelegate.onDeleteButtonTap = { [unowned self] (group: Group) in
            self.deleteGroup(group)
        }

        cloudProgressSyncView.isHidden = true
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        super.prepare(for: segue, sender: sender)

        guard let navController = segue.destination as? UINavigationController else { return }
        switch navController.topViewController {
        case let newStreamVC as NewStreamView:
            dependencyInjector?.initialise(newStreamVC)
        default:
            assertionFailure()
        }
    }

    @objc private func networkReload(_ sender: UIRefreshControl) {
        networkController?.refresh()
    }

    @IBAction func singleTap(_ sender: UITapGestureRecognizer) {
        let point = sender.location(in: collectionView)
        if let indexPath = collectionView.indexPathForItem(at: point) {
            collectionViewDelegate.collectionView(collectionView, didSelectItemAt: indexPath)
        } else {
            collectionViewDelegate.deleteMode(false, for: collectionView)
        }
    }

    @IBAction func longPress(_ sender: UILongPressGestureRecognizer) {
        switch sender.state {
        case .began:
            collectionViewDelegate.deleteMode(true, for: collectionView)
            UISelectionFeedbackGenerator().selectionChanged()
        default:
            break
        }
    }

    private func deleteGroup(_ group: Group) {
        let deleteAction = UIAlertAction(title: "Remove Album", style: .destructive) { _ in
            self.groupManager?.leaveGroup(group) { [weak self] success in
                if success {
                    guard let self = self else { return }
                    self.collectionViewDelegate.deleteMode(false, for: self.collectionView)
                } else {
                    self?.view.makeToastie("There was a problem removing the album. Try again later.", position: .top)
                }
            }
        }
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel) { _ in }
        let message = group.members.isNotEmpty ? "Photos you've shared via this album will no longer be visible to other members." : nil
        let deleteAlert = UIAlertController(title: "Are you sure you want to remove \(group.name)?", message: message, preferredStyle: .alert)
        deleteAlert.addAction(deleteAction)
        deleteAlert.addAction(cancelAction)
        present(deleteAlert, animated: true)
    }
}

extension AlbumsVC: AppContextObserver {
    func reload(inProgress: Bool) {
        if !inProgress, collectionView?.refreshControl?.isRefreshing == .some(true) {
            collectionView?.refreshControl?.endRefreshing()
        }
    }
}

extension AlbumsVC: AssetSyncObserver {
    func update(completedUpdates: Int, totalUpdates: Int) {
        cloudProgressSyncView?.update(completed: completedUpdates, total: totalUpdates)
    }
}

extension AlbumsVC: GroupObserver {
    func new(_ group: Group) {
        collectionViewDelegate.insert(group, into: collectionView)
    }

    func updated(_ oldGroup: Group, to newGroup: Group) {
        collectionViewDelegate.update(oldGroup, with: newGroup, in: collectionView)
    }

    func deleted(_ group: Group) {
        collectionViewDelegate.delete(group, from: collectionView)
//        UserDefaults.standard.removeObject(forKey: "\(group.uuid.string)–NewAlbum")   // FIXME: shouldn't be here! if view is not loaded then this key will not be removed
    }
}

//extension AlbumsVC: UIGestureRecognizerDelegate {
//    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
//        if let isDeleteButton = touch.view?.isKind(of: UIButton.self) {
//            return !isDeleteButton
//        } else {
//            return true
//        }
//    }
//}

extension AlbumsVC {
    class CollectionViewDelegate: NSObject {
        var onSelection: ((Group) -> Void)?
        var onDeleteButtonTap: ((Group) -> Void)?

        private let log = Logger.self
        private let cellReuseIdentifier = "albumCell"
        private let sectionInsets = UIEdgeInsets(top: 10.0, left: 10.0, bottom: 10.0, right: 10.0)
        private let itemsPerRow: CGFloat = 2

        private let assetDataRequester: AssetDataRequester?
        private var groups: [Group]
        private var deleteMode: Bool = false
        private let cache = NSCache<NSUUID, UIImage>()

        init(groups: [Group], assetDataRequester: AssetDataRequester?) {
            self.assetDataRequester = assetDataRequester
            self.groups = groups
            self.cache.countLimit = 25
        }

        func deleteMode(_ deleteMode: Bool, for collectionView: UICollectionView) {
            self.deleteMode = deleteMode
            collectionView.visibleCells.forEach{ ($0 as! AlbumCollectionCell).deleteButton.isHidden = !deleteMode }
        }

        private func cellSize(for collectionView: UICollectionView) -> CGSize {
            let paddingSpace = sectionInsets.left * (itemsPerRow + 1)
            let availableWidth = collectionView.frame.width - paddingSpace
            let widthPerItem = availableWidth / itemsPerRow
            return CGSize(width: widthPerItem, height: widthPerItem + 40)
        }
    }
}

extension AlbumsVC.CollectionViewDelegate {
    func insert(_ group: Group, into collectionView: UICollectionView?) {
        var newItems = [IndexPath]()
        if let index = groups.firstIndex(where: { $0 > group }) {
            groups.insert(group, at: index)
            newItems.append(IndexPath(item: index, section: 0))
        } else {
            groups.append(group)
            newItems.append(IndexPath(item: groups.count - 1, section: 0))
        }
        guard let collectionView = collectionView else { return }
        batchUpdate(collectionView, deletedSections: nil, newSections: nil, movedSection: nil, deletedItems: nil, newItems: newItems, movedItem: nil)
        UIView.animate(withDuration: 0.25) {
            collectionView.alpha = self.groups.isEmpty ? 0 : 1
        }
    }

    func delete(_ group: Group, from collectionView: UICollectionView?) {
        var deletedItems = [IndexPath]()
        if let index = groups.firstIndex(of: group) {
            groups.remove(at: index)
            deletedItems.append(IndexPath(item: index, section: 0))
        }
        guard let collectionView = collectionView else { return }
        batchUpdate(collectionView, deletedSections: nil, newSections: nil, movedSection: nil, deletedItems: deletedItems, newItems: nil, movedItem: nil)
        UIView.animate(withDuration: 0.25) {
            collectionView.alpha = self.groups.isEmpty ? 0 : 1
        }
    }

    func update(_ group: Group, with newGroup: Group, in collectionView: UICollectionView?) {
        if let index = groups.firstIndex(of: group) {
            groups[index] = newGroup
            let movedItem: [IndexPath?] = [
                IndexPath(item: index, section: 0),
                IndexPath(item: index, section: 0)
            ]
            guard let collectionView = collectionView else { return }
            batchUpdate(collectionView, deletedSections: nil, newSections: nil, movedSection: nil, deletedItems: nil, newItems: nil, movedItem: movedItem)
            UIView.animate(withDuration: 0.25) {
                collectionView.alpha = self.groups.isEmpty ? 0 : 1
            }
        } else {
            log.warning("model sync issue, most likely to do with the database queue")
        }
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
        })
    }
}

extension AlbumsVC.CollectionViewDelegate: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if deleteMode {
            deleteMode(false, for: collectionView)
        } else {
            onSelection?(groups[indexPath.item])
        }
    }
}

extension AlbumsVC.CollectionViewDelegate: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return groups.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: cellReuseIdentifier, for: indexPath) as! AlbumCollectionCell
        let group = groups[indexPath.item]

        cell.groupID = group.uuid
        cell.imageView.image = nil
        cell.imageView.contentMode = .scaleAspectFill
        cell.title.text = group.name
        cell.count.text = String(group.album.count)
        cell.deleteButton.isHidden = !deleteMode
        cell.deleteButtonAction = { [weak self] in
            self?.onDeleteButtonTap?(group)
        }
        if let asset = group.album.firstAsset {
            if let image = cache.object(forKey: asset.uuid as NSUUID) {
                cell.imageView.image = image
            } else {
                let imageViewSize = cell.imageView.bounds.size
                let widthRatio = imageViewSize.width / asset.pixelSize.width
                let heightRatio = imageViewSize.height / asset.pixelSize.height
                let ratio = asset.pixelSize.width > asset.pixelSize.height ? heightRatio : widthRatio
                let targetSize = CGSize(width: asset.pixelSize.width * ratio, height: asset.pixelSize.height * ratio)
                assetDataRequester?.requestImage(for: asset, format: .highQuality(targetSize, UIScreen.main.scale)) { [weak self] (image, resultInfo) in
                    guard group.uuid == cell.groupID, let resultInfo = resultInfo else { return }
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
                }
            }
        }
        return cell
    }
}

//extension AlbumDataSource: UICollectionViewDataSourcePrefetching {
//    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
//        let assets = indexPaths.compactMap{ trips[$0.item].album(.default).first }
//        let scale = collectionView.traitCollection.displayScale
//
//        for asset in assets {
//            guard resizedCache.object(forKey: asset.uuid as NSUUID) == nil else {
//                continue
//            }
//            let size =
//            imageManager.requestImage(for: asset, delivery: .opportunistic(size, scale)) { [weak self] image, status in
//                guard let self = self, let image = image else { return }
//                if let rescaled = status?[ImageManager.ResultFlags.isRescaled] as? Bool, rescaled {
//                    self.resizedCache.setObject(image, forKey: asset.uuid as NSUUID)
//                }
//            }
//        }
//    }
//}

extension AlbumsVC.CollectionViewDelegate: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        return cellSize(for: collectionView)
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        return sectionInsets
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        return sectionInsets.left
    }
}

class AlbumCollectionCell: UICollectionViewCell {
    @IBOutlet var imageView: UIImageView!
    @IBOutlet var title: UILabel!
    @IBOutlet var count: UILabel!
    @IBOutlet var deleteButton: UIButton!

    var groupID: UUID!
    var deleteButtonAction: Closure!

    override func awakeFromNib() {
        super.awakeFromNib()
        imageView.layer.cornerRadius = 5
    }

//    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
//        let translatedPoint = deleteButton.convert(point, from: self)
//        if deleteButton.bounds.contains(translatedPoint) {
//            return deleteButton.hitTest(translatedPoint, with: event)
//        }
//        return super.hitTest(point, with: event)
//    }

    @IBAction func deleteAction(_ sender: UIButton) {
        deleteButtonAction()
    }
}
