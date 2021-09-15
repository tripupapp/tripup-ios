//
//  LibraryVC.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 19/08/2020.
//  Copyright © 2020 Vinoth Ramiah. All rights reserved.
//

import Foundation
import UIKit

import TripUpViews

class LibraryVC: UIViewController {
    @IBOutlet var warningHeaderView: WarningHeaderView!
    @IBOutlet var cloudProgressSyncView: CloudProgressSync!
    @IBOutlet var collectionView: UICollectionView!
    @IBOutlet var selectButton: UIButton!
    @IBOutlet var selectionToolbar: UIToolbar!
    @IBOutlet var exportToolbarButton: UIBarButtonItem!
    @IBOutlet var saveToolbarButton: UIBarButtonItem!
    @IBOutlet var deleteToolbarButton: UIBarButtonItem!

    var selectedAssets: [Asset]? {
        guard let indexPaths = collectionView.indexPathsForSelectedItems, indexPaths.isNotEmpty else {
            return nil
        }
        let assets = collectionViewDelegate.items(at: indexPaths)
        return assets.isNotEmpty ? assets : nil
    }

    var pickerMode: Bool = false {
        didSet {
            selectMode = pickerMode
        }
    }

    private lazy var selectionBadgeCounter: BadgeCounter = {
        let badge = BadgeView(color: .systemBlue)
        return badge
    }()

    private var selectMode: Bool = false {
        didSet {
            guard isViewLoaded else {
                return
            }
            configureViews(selectMode: selectMode)
            if !selectMode {
                collectionView.indexPathsForSelectedItems?.forEach { collectionView.deselectItem(at: $0, animated: true) }
            }
        }
    }

    private weak var appContextInfo: AppContextInfo?
    private weak var networkController: NetworkMonitorController?
    private var primaryUserID: UUID!
    private var collectionViewDelegate: CollectionViewDelegate!
    private var assetManager: AssetManager?
    private var userFinder: UserFinder?
    private var autoBackupObserverToken: NSObjectProtocol?
    private var fullscreenVC: FullscreenViewController?

    func initialise(primaryUserID: UUID, assetFinder: AssetFinder, assetObserverRegister: AssetObserverRegister?, assetManager: AssetManager?, userFinder: UserFinder?, appContextInfo: AppContextInfo?, networkController: NetworkMonitorController?) {
        self.primaryUserID = primaryUserID
        self.assetManager = assetManager
        self.userFinder = userFinder
        self.appContextInfo = appContextInfo
        self.networkController = networkController
        self.collectionViewDelegate = CollectionViewDelegate(assetDataRequester: assetManager)

        assetFinder.allAssets { (allAssets) in
            let assets = allAssets.values.filter{ !$0.hidden }
            guard assets.isNotEmpty else {
                return
            }
            DispatchQueue.main.async {
                if let collectionView = self.collectionView {
                    self.collectionViewDelegate.insert(Set(assets), into: collectionView)
                } else {
                    self.collectionViewDelegate.insertPreliminaryData(assets: assets)
                }
            }
        }

        assetManager?.syncTracker.addObserver(self)
        assetObserverRegister?.addObserver(self)

        if #available(iOS 13.0, *) {
            tabBarItem?.image = UIImage(systemName: "photo.on.rectangle")
        }
    }

    deinit {
        assetManager?.syncTracker.removeObserver(self)
        if let autoBackupObserverToken = autoBackupObserverToken {
            NotificationCenter.default.removeObserver(autoBackupObserverToken, name: .AutoBackupChanged, object: nil)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        collectionView.delegate = collectionViewDelegate
        collectionView.dataSource = collectionViewDelegate
//        collectionView.prefetchDataSource = collectionViewDelegate
        collectionView.allowsMultipleSelection = true

        let refreshControl = UIRefreshControl()
        collectionView.refreshControl = refreshControl
        refreshControl.addTarget(self, action: #selector(networkReload), for: .valueChanged)

        collectionViewDelegate.isSelectable = { [unowned self] (asset: Asset) in
            if self.pickerMode {
                return asset.ownerID == self.primaryUserID
            }
            return true
        }
        collectionViewDelegate.onSelection = { [unowned self] (collectionView: UICollectionView, dataModel: PhotoViewDataModel, selectedIndexPath: IndexPath) in
            if !self.selectMode {
                collectionView.deselectItem(at: selectedIndexPath, animated: false)
                let fullscreenVCDelegate = FullscreenViewDelegateLibrary(dataModel: dataModel, primaryUserID: self.primaryUserID, assetManager: self.assetManager, userFinder: self.userFinder)
                let fullscreenVC = UIStoryboard(name: "Photo", bundle: nil).instantiateViewController(withIdentifier: "fullscreenVC") as! FullscreenViewController
                fullscreenVC.initialise(delegate: fullscreenVCDelegate, initialIndex: dataModel.convertToIndex(selectedIndexPath), presenter: self)
                fullscreenVC.onDismiss = { [weak self, unowned fullscreenVC] in
                    if self?.fullscreenVC === fullscreenVC {
                        self?.fullscreenVC = nil
                    }
                }
                self.present(fullscreenVC, animated: false, completion: nil)
                self.fullscreenVC = fullscreenVC
            } else {
                let cell = collectionView.cellForItem(at: selectedIndexPath) as? LibraryCollectionViewCell
                cell?.select()
                self.selectionBadgeCounter.value = collectionView.indexPathsForSelectedItems?.count ?? 0
            }
        }
        collectionViewDelegate.onDeselection = { [unowned self] (collectionView: UICollectionView, _, deselectedIndexPath: IndexPath) in
            guard self.selectMode else {
                return
            }
            let cell = collectionView.cellForItem(at: deselectedIndexPath) as? LibraryCollectionViewCell
            cell?.deselect()
            self.selectionBadgeCounter.value = collectionView.indexPathsForSelectedItems?.count ?? 0
        }
        collectionViewDelegate.onCollectionViewUpdate = { [unowned self] in
            self.view.makeToastieActivity(false)
        }

        if !pickerMode {
            navigationItem.leftBarButtonItems = nil
            navigationItem.rightBarButtonItems = nil

            selectButton.layer.cornerRadius = 5.0
            selectionToolbar.items?.insert(UIBarButtonItem(customView: selectionBadgeCounter), at: 0)
        } else {
            navigationItem.title = nil
            navigationItem.titleView = nil
            navigationItem.rightBarButtonItems?.append(UIBarButtonItem(customView: selectionBadgeCounter))
            selectButton.isHidden = true
        }

        if #available(iOS 13.0, *) {
            exportToolbarButton.image = UIImage(systemName: "square.and.arrow.up")
            saveToolbarButton.image = UIImage(systemName: "square.and.arrow.down")
            deleteToolbarButton.image = UIImage(systemName: "trash")
        }

        warningHeaderView.isHidden = true
        cloudProgressSyncView.isHidden = true

        autoBackupObserverToken = NotificationCenter.default.addObserver(forName: .AutoBackupChanged, object: nil, queue: nil) { [unowned self] _ in
            self.collectionView.reloadItems(at: self.collectionView.indexPathsForVisibleItems)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        let dispatchGroup = DispatchGroup()
        var diskSpaceLow = false
        var cloudSpaceLow = false

        if let appContextInfo = appContextInfo {
            dispatchGroup.enter()
            appContextInfo.lowDiskSpace { lowDiskSpace in
                precondition(Thread.isMainThread)
                diskSpaceLow = lowDiskSpace
                dispatchGroup.leave()
            }
            dispatchGroup.enter()
            appContextInfo.lowCloudStorage { lowCloudStorage in
                precondition(Thread.isMainThread)
                cloudSpaceLow = lowCloudStorage
                dispatchGroup.leave()
            }
        }
        let photoLibraryAccessDenied = appContextInfo?.photoLibraryAccessDenied

        dispatchGroup.notify(queue: .main) {
            self.handle(status: AppContext.Status(diskSpaceLow: diskSpaceLow, cloudSpaceLow: cloudSpaceLow, networkDown: false, photoLibraryAccessDenied: photoLibraryAccessDenied))
        }

        selectionToolbar.frame = tabBarController?.tabBar.frame ?? view.frame
        tabBarController?.view.addSubview(selectionToolbar)
        selectionToolbar.sizeToFit()
    }

    @IBAction func tappedSelectButton(_ sender: UIButton) {
        precondition(!pickerMode)
        selectMode = !selectMode
    }

    @IBAction func selectionToolbarAction(_ sender: UIBarButtonItem) {
        guard let assetManager = assetManager, let selectedAssets = selectedAssets else {
            return
        }
        switch sender {
        case exportToolbarButton:
            export(assets: selectedAssets, assetRequester: assetManager, presentingViewController: self)
        case saveToolbarButton:
            save(assets: selectedAssets, assetService: assetManager, presentingViewController: self)
        case deleteToolbarButton:
            delete(assets: selectedAssets, assetService: assetManager, presentingViewController: self) { [weak self] in
                self?.selectionBadgeCounter.value = 0
            }
        default:
            assertionFailure()
        }
    }

    @objc private func networkReload(_ sender: UIRefreshControl) {
        networkController?.refresh()
    }

    func configureViews(selectMode: Bool) {
        precondition(!pickerMode)
        if !selectMode {
            selectButton.setTitle("Select", for: .normal)
            collectionView.indexPathsForSelectedItems?.forEach {
                if let cell = collectionView.cellForItem(at: $0) as? LibraryCollectionViewCell {
                    cell.deselect()
                }
            }
            selectionToolbar.isHidden = true
            selectionBadgeCounter.value = 0
        } else {
            selectButton.setTitle("Cancel", for: .normal)
            selectionToolbar.isHidden = false
        }
    }
}

extension LibraryVC: AssetActions {}

extension LibraryVC: AppContextObserver {
    func handle(status: AppContext.Status) {
        if status.photoLibraryAccessDenied == .some(true) {
            warningHeaderView.label.text = "TripUp doesn't have full access to your photo library. Allow full access to view, share and backup your photos."
            warningHeaderView.isHidden = false
        } else if status.diskSpaceLow {
            warningHeaderView.label.text = "Your device is running low on disk space. Please remove files or apps to continue."
            warningHeaderView.isHidden = false
        } else if status.cloudSpaceLow {
            warningHeaderView.label.text = "Your cloud storage is full. Please upgrade your storage tier or delete photos to continue."
            warningHeaderView.isHidden = false
        } else {
            warningHeaderView.isHidden = true
        }
    }

    func reload(inProgress: Bool) {
        if inProgress {
            view?.makeToastieActivity(collectionViewDelegate.collectionViewIsEmpty)
        } else {
            view?.makeToastieActivity(false)
            if collectionView?.refreshControl?.isRefreshing == .some(true) {
                collectionView.refreshControl?.endRefreshing()
            }
        }
    }
}

extension LibraryVC: AssetObserver {
    func new(_ assets: Set<Asset>) {
        collectionViewDelegate.insert(assets, into: collectionView)
        fullscreenVC?.new(assets)
    }

    func deleted(_ assets: Set<Asset>) {
        collectionViewDelegate.delete(assets, from: collectionView)
        fullscreenVC?.deleted(assets)
    }

    func updated(_ oldAsset: Asset, to newAsset: Asset) {
        switch (oldAsset.hidden, newAsset.hidden){
        case (false, false):
            collectionViewDelegate.update(oldAsset, with: newAsset, in: collectionView)
            fullscreenVC?.updated(oldAsset, to: newAsset)
        case(false, true):
            collectionViewDelegate.delete([oldAsset], from: collectionView)
            fullscreenVC?.deleted([oldAsset])
        case(true, false):
            collectionViewDelegate.insert([newAsset], into: collectionView)
            fullscreenVC?.new([newAsset])
        case(true, true):
            break
        }
    }
}

extension LibraryVC: AssetSyncObserver {
    func update(completedUpdates: Int, totalUpdates: Int) {
        cloudProgressSyncView?.update(completed: completedUpdates, total: totalUpdates)
    }
}

extension LibraryVC: FullscreenViewTransitionDelegate {
    func transitioning(from index: Int) -> (CGRect, UIImage?) {
        let indexPath = collectionViewDelegate.indexPath(forIndex: index)
        let cell = collectionView.cellForItem(at: indexPath) as! LibraryCollectionViewCell
        let frame = collectionView.convert(cell.frame, to: nil)
        return (frame, cell.imageView.image)
    }

    func transitioning(to index: Int) -> CGRect {
        let indexPath = collectionViewDelegate.indexPath(forIndex: index)
        collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: false)
        let cellLayout = collectionView.layoutAttributesForItem(at: indexPath)! // cannot use cellForItem as cell is not visible
        return collectionView.convert(cellLayout.frame, to: nil)
    }
}

extension LibraryVC {
    class CollectionViewDelegate: NSObject {
        var collectionViewIsEmpty: Bool {
            return dataModel.count == 0
        }

        var isSelectable: ((_ asset: Asset) -> Bool)?
        var onSelection: ((_ collectionView: UICollectionView, _ dataModel: PhotoViewDataModel, _ selectedIndexPath: IndexPath) -> Void)?
        var onDeselection: ((_ collectionView: UICollectionView, _ dataModel: PhotoViewDataModel, _ deselectedIndexPath: IndexPath) -> Void)?
        var onCollectionViewUpdate: Closure?

        private let dateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "dd MMM yyyy, E"
            return formatter
        }()
        private let cellPadding: CGFloat = 1.0
        private let itemsPerRow: CGFloat = 4.0
        private let assetDataRequester: AssetDataRequester?
        private var dataModel: PhotoViewDataModel
        private let cache = NSCache<NSUUID, UIImage>()

        init(assetDataRequester: AssetDataRequester?) {
            self.assetDataRequester = assetDataRequester
            self.dataModel = PhotoViewDataModel(assets: [UUID : Asset](), dateAscending: false)
            self.cache.countLimit = 200
        }

        func insertPreliminaryData<T>(assets: T) where T: Sequence, T.Element == Asset {
            _ = dataModel.insert(assets)
        }

        func indexPath(forIndex index: Int) -> IndexPath {
            let asset = dataModel[index]
            return dataModel.indexPath(for: asset)
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
}

extension LibraryVC.CollectionViewDelegate {
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
            self?.onCollectionViewUpdate?()
            if itemVisibleBeforeUpdate, let newIndexPath = movedItem?[1], collectionView.indexPathsForVisibleItems.contains(newIndexPath) {
                collectionView.reloadItems(at: [newIndexPath])
            }
        })
    }
}

extension LibraryVC.CollectionViewDelegate: UICollectionViewDelegate {
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

extension LibraryVC.CollectionViewDelegate: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        return cellSize(for: collectionView)
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        return cellPadding
    }
}

extension LibraryVC.CollectionViewDelegate: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return dataModel.numberOfItems(inSection: section)
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: LibraryCollectionViewCell.reuseIdentifier, for: indexPath) as! LibraryCollectionViewCell
        cell.imageView.image = nil
        cell.imageView.contentMode = .scaleAspectFill
        if let selectedIndexPaths = collectionView.indexPathsForSelectedItems, Set(selectedIndexPaths).contains(indexPath) {
            cell.select()
        } else {
            cell.deselect()
        }

        let asset = dataModel.item(at: indexPath)
        cell.assetID = asset.uuid
        cell.durationLabel.text = asset.duration?.formattedString
        cell.importedIcon.isHidden = !asset.imported
        cell.importingIcon.isHidden = !cell.importedIcon.isHidden || !UserDefaults.standard.bool(forKey: UserDefaultsKey.AutoBackup.rawValue)
        cell.topGradient.isHidden = cell.topIconsHidden
        cell.bottomGradient.isHidden = cell.bottomIconsHidden
        cell.lockView.isHidden = isSelectable?(asset) ?? true

        if #available(iOS 13.0, *) {
            cell.activityIndicator.style = .medium
            cell.lockIcon.image = UIImage(systemName: "lock")
            cell.importingIcon.image = UIImage(systemName: "arrow.up.circle")
            cell.importedIcon.image = UIImage(systemName: "cloud")
        }
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
            let headerView = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: PhotoViewSectionHeader.reuseIdentifier, for: indexPath) as! PhotoViewSectionHeader
            headerView.day.text = dateFormatter.string(from: sectionKey)
            return headerView
        case UICollectionView.elementKindSectionFooter:
            let footerView = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: PhotoViewSectionFooter.reuseIdentifier, for: indexPath) as! PhotoViewSectionFooter
            return footerView
        default:
            fatalError("viewForSupplementaryElementOfKind value: \(kind) is invalid")
        }
    }
}

extension LibraryVC.CollectionViewDelegate: UICollectionViewDataSourcePrefetching {
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

class LibraryCollectionViewCell: UICollectionViewCell {
    static let reuseIdentifier = "AssetCell"

    @IBOutlet var imageView: UIImageView!
    @IBOutlet var activityIndicator: UIActivityIndicatorView!
    @IBOutlet var topGradient: UIGradientView!
    @IBOutlet var bottomGradient: UIGradientView!
    @IBOutlet var checkmarkView: UIImageView!
    @IBOutlet var lockView: UIView!
    @IBOutlet var lockIcon: UIImageView!

    @IBOutlet var durationLabel: UILabel!
    // use 2 separate icons for this, because we use System Symbols in iOS 13+, which don't behave well when switching image with different aspect ratio
    @IBOutlet var importedIcon: UIImageView!
    @IBOutlet var importingIcon: UIImageView!

    var assetID: UUID!
    var topIconsHidden: Bool {
        return durationLabel.text?.isEmpty ?? true
    }
    var bottomIconsHidden: Bool {
        return importedIcon.isHidden && importingIcon.isHidden
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        /*
         tintColorDidChange fixes tintColor not being set from storyboard when cell is first created (seems fine once a cell is reused though)
         https://stackoverflow.com/questions/41121425/uiimageview-doesnt-always-tint-template-image - apple radar: http://www.openradar.me/radar?id=5005434293321728
         https://stackoverflow.com/questions/52992077/uiimageview-tint-color-weirdness - apple radar: http://openradar.appspot.com/23759908
         not sure which one is the issue
         - This issue did not appear in XCode 9, iOS 11 SDK, iPhone X running iOS 11.4.1
         - Only presented itself once upgraded to XCode 10, still on iOS 11 SDK, iPhone X running iOS 11.4.1
         - Fixed in Xcode 11.3.1: fixed for iOS 13.3 iPhone X simulator, still broken for iOS 12.4 iPhone 5S simulator
        */
        if #available(iOS 13.0, *) {} else {
            importedIcon.tintColorDidChange()
            importingIcon.tintColorDidChange()
        }
    }

    func select() {
        checkmarkView.isHidden = false
        imageView.alpha = 0.75
    }

    func deselect() {
        checkmarkView.isHidden = true
        imageView.alpha = 1.0
    }
}
