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
    @IBOutlet var selectionCountToolbarItem: UIBarButtonItem!
    @IBOutlet var selectionPlaceholderToolbarItem: UIBarButtonItem!
    @IBOutlet var selectionExportToolbarItem: UIBarButtonItem!
    @IBOutlet var selectionSaveToolbarItem: UIBarButtonItem!
    @IBOutlet var selectionDeleteToolbarItem: UIBarButtonItem!

    lazy var selectionBadgeCounter: BadgeCounter = {
        let badge = BadgeView(color: .systemBlue)
        return badge
    }()

    var collectionViewDelegate: CollectionViewDelegate!
    var pickerMode: Bool = false {
        didSet {
            selectMode = pickerMode
        }
    }
    var selectMode: Bool = false {
        didSet {
            if isViewLoaded {
                enterSelectMode(selectMode)
            }
        }
    }

    private weak var appContextInfo: AppContextInfo?
    private weak var networkController: NetworkMonitorController?
    private var primaryUserID: UUID!
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
        self.collectionViewDelegate = CollectionViewDelegate(
            assetDataRequester: assetManager,
            dateAscending: false,
            cellReuseIdentifier: LibraryCollectionViewCell.reuseIdentifier
        )

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

        let isSelectable = { [unowned self] (asset: Asset) -> Bool in
            if self.pickerMode {
                return asset.ownerID == self.primaryUserID
            }
            return true
        }
        collectionViewDelegate.cellConfiguration = { (cell: CollectionViewCell, asset: Asset) in
            let cell = cell as! LibraryCollectionViewCell
            cell.importedIcon.isHidden = !asset.imported
            cell.importingIcon.isHidden = !cell.importedIcon.isHidden || !UserDefaults.standard.bool(forKey: UserDefaultsKey.AutoBackup.rawValue)
            cell.lockView.isHidden = isSelectable(asset)

            if #available(iOS 13.0, *) {
                cell.lockIcon.image = UIImage(systemName: "lock")
                cell.importingIcon.image = UIImage(systemName: "arrow.up.circle")
                cell.importedIcon.image = UIImage(systemName: "cloud")
            }
        }
        collectionViewDelegate.isSelectable = isSelectable
        collectionViewDelegate.onSelection = { [unowned self] (collectionView: UICollectionView, dataModel: CollectionViewDataModel, selectedIndexPath: IndexPath) in
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
                self.selectCell(true, atIndexPath: selectedIndexPath)
            }
        }
        collectionViewDelegate.onDeselection = { [unowned self] (collectionView: UICollectionView, _, deselectedIndexPath: IndexPath) in
            if self.selectMode {
                self.selectCell(false, atIndexPath: deselectedIndexPath)
            }
        }
        collectionViewDelegate.onCollectionViewUpdate = { [unowned self] in
            self.view.makeToastieActivity(false)
        }

        if !pickerMode {
            navigationItem.leftBarButtonItems = nil
            navigationItem.rightBarButtonItems = nil

            selectButton.layer.cornerRadius = 5.0
            selectionCountToolbarItem.title = nil
            selectionCountToolbarItem.customView = selectionBadgeCounter
            selectionPlaceholderToolbarItem.title = nil
            selectionPlaceholderToolbarItem.image = nil
            if #available(iOS 13.0, *) {
                selectionExportToolbarItem.image = UIImage(systemName: "square.and.arrow.up")
                selectionSaveToolbarItem.image = UIImage(systemName: "square.and.arrow.down")
                selectionDeleteToolbarItem.image = UIImage(systemName: "trash")
            }
        } else {
            navigationItem.title = nil
            navigationItem.titleView = nil
            navigationItem.rightBarButtonItems?.append(UIBarButtonItem(customView: selectionBadgeCounter))
            selectButton.isHidden = true
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

        tabBarController?.setToolbarItems(selectionToolbar.items, animated: false)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        tabBarController?.setToolbarItems(nil, animated: false)
    }

    @objc private func networkReload(_ sender: UIRefreshControl) {
        networkController?.refresh()
    }
}

extension LibraryVC: AssetActions {}

extension LibraryVC: CollectionViewMultiSelect {
    func hideSelectionToolbar(_ hide: Bool) {
        tabBarController?.navigationController?.setToolbarHidden(hide, animated: false)
    }

    @IBAction func selectButtonTapped(_ sender: UIButton) {
        precondition(!pickerMode)
        selectMode.toggle()
        tabBarController?.tabBar.isHidden = selectMode
    }

    @IBAction func selectionToolbarAction(_ sender: UIBarButtonItem) {
        guard let assetManager = assetManager, let selectedAssets = selectedAssets else {
            return
        }
        switch sender {
        case selectionExportToolbarItem:
            export(assets: selectedAssets, assetRequester: assetManager, presentingViewController: self)
        case selectionSaveToolbarItem:
            save(assets: selectedAssets, assetService: assetManager, presentingViewController: self)
        case selectionDeleteToolbarItem:
            delete(assets: selectedAssets, assetService: assetManager, presentingViewController: self) { [weak self] in
                self?.selectionBadgeCounter.value = 0
            }
        default:
            assertionFailure()
        }
    }
}

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
