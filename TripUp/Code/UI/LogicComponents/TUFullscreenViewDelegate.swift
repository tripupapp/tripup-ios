//
//  TUFullscreenViewDelegate.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 11/09/2019.
//  Copyright © 2019 Vinoth Ramiah. All rights reserved.
//

import Foundation
import UIKit

class TUFullscreenViewDelegate {
    let bottomToolbarItems: [UIBarButtonItem]?  // use item references from here, as the actual UIToolbar items array may contain spacers
    weak var ownerLabel: UILabel?

    fileprivate let primaryUserID: UUID
    fileprivate var assets: [Asset] {
        return dataModel.allItems
    }

    private let assetRequester: AssetDataRequester?
    private let userFinder: UserFinder?
    private let cache = NSCache<NSUUID, UIImage>()
    private var dataModel: PhotoViewDataModel

    init(primaryUserID: UUID, dataModel: PhotoViewDataModel, assetRequester: AssetDataRequester?, userFinder: UserFinder?, bottomToolbarItems: [UIBarButtonItem]?) {
        self.primaryUserID = primaryUserID
        self.dataModel = dataModel
        self.assetRequester = assetRequester
        self.userFinder = userFinder
        self.cache.countLimit = 30
        self.bottomToolbarItems = bottomToolbarItems
    }

    func configureOverlayViews(forItemAt index: Int) {
        let asset = assets[index]
        if asset.ownerID == primaryUserID {
            ownerLabel?.text = ""
        } else {
            ownerLabel?.text = " 📸 \(userFinder?.user(for: asset.ownerID)?.localContact?.name ?? "Tripper") "
        }
    }

    func bottomToolbarAction(_ fullscreenVC: FullscreenViewController, button: UIBarButtonItem, itemIndex: Int) {}
}

extension TUFullscreenViewDelegate: FullscreenViewDelegate {
    var modelCount: Int {
        return assets.count
    }

    var modelIsEmpty: Bool {
        return assets.isEmpty
    }

    func fullsizeOfItem(at index: Int) -> CGSize {
        return assets[index].pixelSize
    }

    func configure(cell: FullscreenViewCell, forItemAt index: Int) {
        let asset = assets[index]

        cell.assetID = asset.uuid
        cell.imageView.image = nil
        cell.originalMissingLabel.isHidden = true
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
            assetRequester?.requestImage(for: asset, format: .highQuality(targetSize, UIScreen.main.scale)) { [weak self] (image, resultInfo) in
                guard cell.assetID == asset.uuid, let resultInfo = resultInfo else { return }
                if resultInfo.final {
                    if let image = image {
                        if let cache = self?.cache, cache.object(forKey: asset.uuid as NSUUID) == nil {
                            cache.setObject(image, forKey: asset.uuid as NSUUID)
                        }
                        cell.imageView.image = image
                    } else {
                        cell.originalMissingLabel.isHidden = false
                    }
                    cell.activityIndicator.stopAnimating()
                } else if cell.imageView.image == nil {
                    cell.imageView.image = image
                }
            }
        }
    }

    func prefetchItems(at indexes: [Int]) {
        for index in indexes {
            let asset = assets[index]
            guard cache.object(forKey: asset.uuid as NSUUID) == nil else { continue }
            let imageViewSize = UIScreen.main.bounds.size
            let widthRatio = imageViewSize.width / asset.pixelSize.width
            let heightRatio = imageViewSize.height / asset.pixelSize.height
            let ratio = asset.pixelSize.width > asset.pixelSize.height ? heightRatio : widthRatio
            let targetSize = CGSize(width: asset.pixelSize.width * ratio, height: asset.pixelSize.height * ratio)
            assetRequester?.requestImage(for: asset, format: .highQuality(targetSize, UIScreen.main.scale)) { [weak self] (image, resultInfo) in
                guard let self = self else { return }
                guard let image = image, let resultInfo = resultInfo, resultInfo.final, self.cache.object(forKey: asset.uuid as NSUUID) == nil else { return }
                self.cache.setObject(image, forKey: asset.uuid as NSUUID)
            }
        }
    }

    func insert(_ newAssets: Set<Asset>) -> [IndexPath] {
        _ = dataModel.insert(newAssets)

        let newIndexPaths = assets.enumerated()
            .filter{ newAssets.contains($0.element) }
            .map{ IndexPath(item: $0.offset, section: 0) }
        return newIndexPaths
    }

    func remove(_ deletedAssets: Set<Asset>) -> [IndexPath] {
        let deletedIndexPaths = assets.enumerated()
            .filter{ deletedAssets.contains($0.element) }
            .map{ IndexPath(item: $0.offset, section: 0) }

        _ = dataModel.remove(deletedAssets)
        return deletedIndexPaths
    }

    func update(_ oldAsset: Asset, with newAsset: Asset) -> IndexPath {
        if let index = assets.firstIndex(of: oldAsset) {
            _ = dataModel.update(oldAsset, to: newAsset)
            return IndexPath(item: index, section: 0)
        } else {
            return insert(Set([newAsset])).first!
        }
    }
}

class FullscreenViewDelegateLibrary: TUFullscreenViewDelegate {
    private let assetManager: AssetManager?

    init(dataModel: PhotoViewDataModel, primaryUserID: UUID, assetManager: AssetManager?, userFinder: UserFinder?) {
        self.assetManager = assetManager

        var bottomToolbarImages: [UIImage?]!
        if #available(iOS 13.0, *) {
            bottomToolbarImages = [UIImage(systemName: "square.and.arrow.up"), UIImage(systemName: "square.and.arrow.down"), UIImage(systemName: "trash")]
        } else {
            bottomToolbarImages = [UIImage(named: "share-outline-toolbar"), UIImage(named: "download-outline-toolbar"), UIImage(named: "trash-toolbar")]
        }
        let bottomToolbarButtons = bottomToolbarImages.map{ UIBarButtonItem(image: $0, style: .plain, target: nil, action: nil) }

        super.init(primaryUserID: primaryUserID, dataModel: dataModel, assetRequester: assetManager, userFinder: userFinder, bottomToolbarItems: bottomToolbarButtons)
    }

    override func bottomToolbarAction(_ fullscreenVC: FullscreenViewController, button: UIBarButtonItem, itemIndex: Int) {
        let asset = assets[itemIndex]
        switch button {
        case bottomToolbarItems![0]: // EXPORT
            let item = AssetActivityItemProvider(asset: asset, assetDataRequester: assetManager!)
            let activityController = UIActivityViewController(activityItems: [item], applicationActivities: nil)
            activityController.completionWithItemsHandler = { _, _, _, error in
                if error != nil {
                    fullscreenVC.view.makeToastie("Unable to retrieve the full quality for this photo. Check your internet connection and try again.", position: .top)
                }
            }
            activityController.excludedActivityTypes = [.saveToCameraRoll]
            fullscreenVC.present(activityController, animated: true, completion: nil)
        case bottomToolbarItems![1]: // SAVE
            assetManager?.saveToIOS(asset: asset) { (saved, wasAlreadySaved) in
                let message: String = {
                    if wasAlreadySaved {
                        return "Photo already saved to device photo library"
                    } else if saved {
                        return "Saved to device photo library"
                    } else {
                        return "Unable to save to device photo library. Check your network connection and try again"
                    }
                }()
                fullscreenVC.view.makeToastie(message, position: .top)
            }
        case bottomToolbarItems![2]: // DELETE
            let deleteAction = UIAlertAction(title: "Delete", style: .destructive) { _ in
                self.assetManager?.delete([asset])
            }
            let cancelAction = UIAlertAction(title: "Cancel", style: .cancel) { _ in }
            let deleteAlert = UIAlertController(title: nil, message: "Photo will be removed from all albums", preferredStyle: .actionSheet)
            deleteAlert.addAction(deleteAction)
            deleteAlert.addAction(cancelAction)
            fullscreenVC.present(deleteAlert, animated: true)
        default:
            assertionFailure()
            break
        }
    }
}

class FullscreenViewDelegateGroup: TUFullscreenViewDelegate {
    var group: Group

    private let assetManager: AssetManager?
    private let groupManager: GroupManager?

    init(group: Group, primaryUserID: UUID, dataModel: PhotoViewDataModel, assetManager: AssetManager?, groupManager: GroupManager?, userFinder: UserFinder?) {
        self.group = group
        self.assetManager = assetManager
        self.groupManager = groupManager

        var bottomToolbarImages: [UIImage?]!
        if #available(iOS 13.0, *) {
            bottomToolbarImages = [UIImage(systemName: "eye"), UIImage(systemName: "square.and.arrow.up"), UIImage(systemName: "square.and.arrow.down"), UIImage(systemName: "trash")]
        } else {
            bottomToolbarImages = [UIImage(named: "eye-outline-toolbar"), UIImage(named: "share-outline-toolbar"), UIImage(named: "download-outline-toolbar"), UIImage(named: "trash-toolbar")]
        }
        let bottomToolbarButtons = bottomToolbarImages.map{ UIBarButtonItem(image: $0, style: .plain, target: nil, action: nil) }

        super.init(primaryUserID: primaryUserID, dataModel: dataModel, assetRequester: assetManager, userFinder: userFinder, bottomToolbarItems: bottomToolbarButtons)
    }

    override func configureOverlayViews(forItemAt index: Int) {
        super.configureOverlayViews(forItemAt: index)
        let asset = assets[index]
        if asset.ownerID == primaryUserID {
            let shared = group.album.sharedAssets[asset.uuid] != nil
            bottomToolbarItems?.first?.tintColor = shared ? .systemBlue : .white
            bottomToolbarItems?.first?.isEnabled = true
        } else {
            bottomToolbarItems?.first?.tintColor = .clear
            bottomToolbarItems?.first?.isEnabled = false
        }
    }

    override func bottomToolbarAction(_ fullscreenVC: FullscreenViewController, button: UIBarButtonItem, itemIndex: Int) {
        let asset = assets[itemIndex]
        switch button {
        case bottomToolbarItems![0]: // TOGGLE SHARE STATE
            if group.album.sharedAssets[asset.uuid] == nil {
                groupManager?.shareAssets([asset], withGroup: group) { success in
                    if !success {
                        fullscreenVC.view.makeToastie("There was a problem sharing this photo with the group", position: .top)
                    }
                }
            } else {
                groupManager?.unshareAssets([asset], fromGroup: group) { success in
                    if !success {
                        fullscreenVC.view.makeToastie("There was a problem unsharing this photo from the group", position: .top)
                    }
                }
            }
        case bottomToolbarItems![1]: // EXPORT
            let item = AssetActivityItemProvider(asset: asset, assetDataRequester: assetManager!)
            let activityController = UIActivityViewController(activityItems: [item], applicationActivities: nil)
            activityController.completionWithItemsHandler = { _, _, _, error in
                if error != nil {
                    fullscreenVC.view.makeToastie("Unable to retrieve the full quality for this photo. Check your internet connection and try again.", position: .top)
                }
            }
            activityController.excludedActivityTypes = [.saveToCameraRoll]
            fullscreenVC.present(activityController, animated: true, completion: nil)
        case bottomToolbarItems![2]: // SAVE
            assetManager?.saveToIOS(asset: asset) { (saved, wasAlreadySaved) in
                let message: String = {
                    if wasAlreadySaved {
                        return "Photo already saved to device photo library"
                    } else if saved {
                        return "Saved to device photo library"
                    } else {
                        return "Unable to save to device photo library. Check your network connection and try again"
                    }
                }()
                fullscreenVC.view.makeToastie(message, position: .top)
            }
        case bottomToolbarItems![3]: // DELETE
            let ownedAsset = asset.ownerID == primaryUserID
            let deleteAction = UIAlertAction(title: ownedAsset ? "Delete" : "Delete for Me", style: .destructive) { _ in
                self.assetManager?.delete([asset])
            }
            let cancelAction = UIAlertAction(title: "Cancel", style: .cancel) { _ in }
            let deleteAlert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
            if ownedAsset {
                let removeAction = UIAlertAction(title: "Remove from Album", style: .destructive) { _ in
                    self.groupManager?.removeAssets([asset], from: self.group) { success in
                        if !success {
                            fullscreenVC.view.makeToastie("Error removing photo from album", position: .top)
                        }
                    }
                }
                deleteAlert.addAction(removeAction)
            }
            deleteAlert.addAction(deleteAction)
            deleteAlert.addAction(cancelAction)
            fullscreenVC.present(deleteAlert, animated: true)
        default:
            assertionFailure()
            break
        }
    }
}
