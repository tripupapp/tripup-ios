//
//  PhotoView.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 19/07/2017.
//  Copyright © 2017 Vinoth Ramiah. All rights reserved.
//

import Foundation
import UIKit

import TripUpViews

class PhotoView: UIViewController {
    @IBOutlet var inAppGuideContainerView: UIView!
    @IBOutlet var collectionView: UICollectionView!
    @IBOutlet var swipePhotoGesture: UIPanGestureRecognizer!
    @IBOutlet var selectButton: UIButton!

    @IBOutlet var selectionToolbar: UIToolbar!
    @IBOutlet var selectionCountToolbarItem: UIBarButtonItem!
    @IBOutlet var selectionShareToolbarItem: UIBarButtonItem!
    @IBOutlet var selectionExportToolbarItem: UIBarButtonItem!
    @IBOutlet var selectionSaveToolbarItem: UIBarButtonItem!
    @IBOutlet var selectionDeleteToolbarItem: UIBarButtonItem!

    lazy var selectionBadgeCounter: BadgeCounter = {
        let badge = BadgeView(color: .systemBlue)
        return badge
    }()

    var collectionViewDelegate: CollectionViewDelegate!
    var group: Group! {
        didSet {
            if oldValue == nil {
                self.collectionViewDelegate.insertPreliminaryData(assets: group.album.pics.values)
            }
            if let fullscreenVC = self.fullscreenVC, let delegate = fullscreenVC.delegate as? FullscreenViewDelegateGroup {
                delegate.group = group
                if let indexPath = fullscreenVC.collectionView.indexPathsForVisibleItems.first {
                    delegate.configureOverlayViews(forItemAt: indexPath.item)
                }
            }
        }
    }
    var selectMode: Bool = false {
        didSet {
            configureSelectMode()
        }
    }
    var lastLongPressedIndexPath: IndexPath?
    var scrollingAnimator: UIViewPropertyAnimator?
    var multiselectScrollingDown: Bool?

    fileprivate var swipeThresholdActivation: CGFloat {
        let viewWidth = collectionView.frame.width
        let cellWidth = viewWidth / collectionViewDelegate.itemsPerRow
        return cellWidth / 4
    }

    private weak var networkController: NetworkMonitorController?

    private let log = Logger.self
    private var primaryUserID: UUID!
    private var assetManager: AssetManager?
    private var groupManager: GroupManager?
    private var userFinder: UserFinder?
    private var appContextInfo: AppContextInfo?
    private var dependencyInjector: DependencyInjector?

    private var selectedIndexesForGesture: [IndexPath]?
    private var swipeCellFeedback: UISelectionFeedbackGenerator?
    private var runningGestureTutorial = false
    private var fullscreenVC: FullscreenViewController?

    func initialise(primaryUserID: UUID, groupManager: GroupManager?, groupObserverRegister: GroupObserverRegister?, assetManager: AssetManager?, userFinder: UserFinder?, networkController: NetworkMonitorController?, appContextInfo: AppContextInfo?, dependencyInjector: DependencyInjector?) {
        self.primaryUserID = primaryUserID
        self.assetManager = assetManager
        self.groupManager = groupManager
        self.userFinder = userFinder
        self.networkController = networkController
        self.appContextInfo = appContextInfo
        self.dependencyInjector = dependencyInjector
        self.collectionViewDelegate = CollectionViewDelegate(
            assetDataRequester: assetManager,
            cellReuseIdentifier: AlbumCollectionViewCell.reuseIdentifier
        )

        groupObserverRegister?.addObserver(self)
    }

    func assertDependencies() {
        assert(group != nil)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        assertDependencies()

        collectionView.alpha = group.album.isEmpty ? 0 : 1
        collectionView.delegate = collectionViewDelegate
        collectionView.dataSource = collectionViewDelegate
//        collectionView.prefetchDataSource = collectionViewDelegate
        collectionView.allowsMultipleSelection = true

        collectionViewDelegate.cellConfiguration = { [unowned self] (cell: CollectionViewCell, asset: Asset) in
            let cell = cell as! AlbumCollectionViewCell
            let shared = self.group.album.sharedAssets[asset.uuid] != nil
            cell.shareIcon.isHidden = !shared

            if asset.ownerID == self.primaryUserID {
                cell.shareActionIconConstraint.isZoomed = shared
                cell.unshareActionIconConstraint.isZoomed = !shared
            } else {
                cell.shareActionIcon.image = UIImage(systemName: "lock.circle")
                cell.unshareActionIcon.image = UIImage(systemName: "lock.circle")
                cell.shareActionIconConstraint.isZoomed = true
                cell.unshareActionIconConstraint.isZoomed = true
            }
            cell.assetContents.isHidden = false // set to hidden in storyboard, but why?
        }
        collectionViewDelegate.onSelection = { [unowned self] (collectionView: UICollectionView, dataModel: CollectionViewDataModel, selectedIndexPath: IndexPath) in
            if !self.selectMode {
                let fullscreenVCDelegate = FullscreenViewDelegateGroup(group: self.group, primaryUserID: self.primaryUserID, dataModel: dataModel, assetManager: self.assetManager, groupManager: self.groupManager, userFinder: self.userFinder)
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
                self.shareToolbarButtonState()
            }
        }
        collectionViewDelegate.onDeselection = { [unowned self] (collectionView: UICollectionView, _, deselectedIndexPath: IndexPath) in
            if self.selectMode {
                self.selectCell(false, atIndexPath: deselectedIndexPath)
                self.shareToolbarButtonState()
            }
        }
        collectionViewDelegate.onCollectionViewUpdate = { [unowned self] in
            UIView.animate(withDuration: 0.25) {
                collectionView.alpha = self.collectionViewDelegate.collectionViewIsEmpty ? 0 : 1
            }
        }

        self.title = group.name
        let userSelectionButton = UIBarButtonItem(image: UIImage(systemName: "person.badge.plus.fill"), style: .plain, target: self, action: #selector(PhotoView.loadUserSelection))
        self.navigationItem.leftItemsSupplementBackButton = true
        self.navigationItem.leftBarButtonItems = [userSelectionButton]
        let addFromIOSButton = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(PhotoView.photoPicker))
        self.navigationItem.rightBarButtonItems = [addFromIOSButton]

        let refreshControl = UIRefreshControl()
        collectionView.refreshControl = refreshControl
        refreshControl.addTarget(self, action: #selector(networkReload(_:)), for: .valueChanged)

        selectButton.layer.cornerRadius = 5.0
        selectionCountToolbarItem.title = nil
        selectionCountToolbarItem.customView = selectionBadgeCounter

//        if let child = children.first(where: { $0 is GuideBox }), let guideBoxVC = child as? GuideBox, UserDefaults.standard.bool(forKey: "\(group.uuid.string)–NewAlbum") {
//            guideBoxVC.removeFromPhotoView()
//            inAppGuideContainerView.removeFromSuperview()
//        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tabBarController?.setToolbarItems(selectionToolbar.items, animated: false)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        #if DEBUG
        let screenshotEnv = ProcessInfo.processInfo.environment["UITest-Screenshots"] != nil
        showGestureTutorial(simulate: screenshotEnv)
        #else
        showGestureTutorial()
        #endif
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        tabBarController?.setToolbarItems(nil, animated: false)
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        super.prepare(for: segue, sender: sender)
//        if let guideViewController = segue.destination as? GuideBox {
//            guideViewController.dismissCallback = { [unowned self] in
//                self.inAppGuideContainerView.removeFromSuperview()
////                UserDefaults.standard.set(true, forKey: "\(self.group.uuid.string)–NewAlbum")
//            }
//        }
    }

    @IBAction func cancel(_ unwindSegue: UIStoryboardSegue) {}

    @IBAction func done(_ unwindSegue: UIStoryboardSegue) {
        guard let libraryVC = unwindSegue.source as? LibraryVC, let unwindSegue = unwindSegue as? UIStoryboardSegueWithCompletion else { return }
        guard let selectedAssets = libraryVC.selectedAssets else { return }
        let newAssets = Set(selectedAssets).subtracting(group.album.pics.values)
        guard newAssets.isNotEmpty else { return }
        unwindSegue.completion = {
            self.log.debug("Add \(newAssets.count) assets to group")
            let addAction = UIAlertAction(title: "Just Add", style: .default) { _ in
                self.view.makeToastieActivity(true)
                self.groupManager?.addAssets(newAssets, to: self.group, share: false) { [weak self] success in
                    self?.view.makeToastieActivity(false)
                }
            }
            let addAndShareAction = UIAlertAction(title: "Share Photos", style: .default) { _ in
                self.view.makeToastieActivity(true)
                self.groupManager?.addAssets(newAssets, to: self.group, share: true) { [weak self] success in
                    self?.view.makeToastieActivity(false)
                }
            }
            let message = "\(newAssets.count) new photos selected"
            let shareAlert = UIAlertController(title: "Share selected photos with other members of \(self.group.name)?", message: message, preferredStyle: .alert)
            shareAlert.addAction(addAction)
            shareAlert.addAction(addAndShareAction)
            self.present(shareAlert, animated: true)
        }
    }

    @objc private func loadUserSelection() {
        let storyboard = UIStoryboard(name: "Albums", bundle: nil)
        let userSelectionView = storyboard.instantiateViewController(withIdentifier: "UserSelection") as! UserSelectionView
        dependencyInjector?.initialise(userSelectionView)
        userSelectionView.loadModally = true
        userSelectionView.preselectedIDs = group.members.map{ $0.uuid }
        userSelectionView.delegate = self
        let navigationController = UINavigationController(rootViewController: userSelectionView)
        present(navigationController, animated: true, completion: nil)
    }

    @objc private func networkReload(_ sender: UIRefreshControl) {
        networkController?.refresh()
    }

    @objc func photoPicker(_ sender: UIBarButtonItem!) {
        let libraryVCNavController = UIStoryboard(name: "Library", bundle: nil).instantiateInitialViewController() as! UINavigationController
        let libraryVC = libraryVCNavController.topViewController as! LibraryVC
        dependencyInjector?.initialise(libraryVC)
        libraryVC.pickerMode = true
        present(libraryVCNavController, animated: true, completion: nil)
//        if let appContextInfo = appContextInfo {
//            appContextInfo.lowCloudStorage { [weak self] lowCloudStorage in
//                guard let self = self else { return }
//                if lowCloudStorage {
//                    let inAppPurchaseView = UIStoryboard(name: "InAppPurchase", bundle: nil).instantiateInitialViewController() as! InAppPurchaseView
//                    self.dependencyInjector?.initialise(inAppPurchaseView: inAppPurchaseView)
//                    inAppPurchaseView.modalPresentationStyle = .overFullScreen
//                    inAppPurchaseView.modalTransitionStyle = .crossDissolve
//                    self.present(inAppPurchaseView, animated: true, completion: nil)
//                } else {
//                    self.photoPicker.present(from: self)
//                }
//            }
//        } else {
//            photoPicker.present(from: self)
//        }
    }

    private func indexes(for recognizer: UIGestureRecognizer) -> [IndexPath]? {
        if let indexPath = collectionView.indexPathForItem(at: recognizer.location(in: collectionView)) {
            return [indexPath]
        }
        return nil
    }

    private func showGestureTutorial(simulate: Bool = false) {
        guard !UserDefaults.standard.bool(forKey: UserDefaultsKey.GestureTutorialPlayed.rawValue) || simulate else {
            return
        }
        guard group.album.isNotEmpty, !runningGestureTutorial else {
            return
        }
        runningGestureTutorial = true

        let message = """
        👆➡️ Drag photo to the right to share it

        👆⬅️ Drag photo to the left to hide it
        """

        let alert = UIAlertController(title: message, message: nil, preferredStyle: .alert)
        let action = UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            self?.runningGestureTutorial = false
            UserDefaults.standard.set(true, forKey: UserDefaultsKey.GestureTutorialPlayed.rawValue)
        }
        alert.addAction(action)
        self.present(alert, animated: true, completion: nil)

        runGestureTutorial(afterDelay: 1.0, simulate: simulate)
    }

    private func runGestureTutorial(afterDelay delay: TimeInterval, simulate: Bool = false) {
        guard runningGestureTutorial else {
            return
        }
        let indexPath = IndexPath(item: 0, section: 0)
        guard let cell = collectionView.cellForItem(at: indexPath) as? AlbumCollectionViewCell else {
            return
        }
        let point = cell.frame.width / 2
        let originX = cell.assetContents.frame.origin.x

        let shareBlock = {
            cell.assetContents.frame.origin.x = point
            cell.shareActionIconConstraint.isZoomed = true
            cell.actionIconContents.layoutIfNeeded()
        }
        let unshareBlock = {
            cell.assetContents.frame.origin.x = -point
            cell.unshareActionIconConstraint.isZoomed = true
            cell.actionIconContents.layoutIfNeeded()
        }
        let resetBlock = {
            cell.assetContents.frame.origin.x = originX
            cell.shareActionIconConstraint.isZoomed = false
            cell.unshareActionIconConstraint.isZoomed = false
            cell.actionIconContents.layoutIfNeeded()
        }

        guard !simulate else {
            cell.showActionIcon(share: true)
            shareBlock()
            return
        }

        let shareAnimator = UIViewPropertyAnimator(duration: 0.5, curve: .linear) {
            shareBlock()
        }
        let resetShareAnimator = UIViewPropertyAnimator(duration: 0.2, curve: .linear) {
            resetBlock()
        }
        let unshareAnimator = UIViewPropertyAnimator(duration: 0.5, curve: .linear) {
            unshareBlock()
        }
        let resetUnshareAnimator = UIViewPropertyAnimator(duration: 0.2, curve: .linear) {
            resetBlock()
        }
        shareAnimator.addCompletion { (_) in
            resetShareAnimator.startAnimation(afterDelay: 0.2)
        }
        resetShareAnimator.addCompletion { [weak self] (_) in
            if self?.runningGestureTutorial == .some(true) {
                cell.showActionIcon(share: false)
                unshareAnimator.startAnimation(afterDelay: 0.5)
            }
        }
        unshareAnimator.addCompletion { (_) in
            resetUnshareAnimator.startAnimation(afterDelay: 0.2)
        }
        resetUnshareAnimator.addCompletion { [weak self] (_) in
            if self?.runningGestureTutorial == .some(true) {
                self?.runGestureTutorial(afterDelay: 0.5)
            }
        }
        cell.showActionIcon(share: true)
        shareAnimator.startAnimation(afterDelay: delay)
    }
}

extension PhotoView: AssetActions {}

extension PhotoView: CollectionViewMultiSelect {
    func hideSelectionToolbar(_ hide: Bool) {
        tabBarController?.navigationController?.setToolbarHidden(hide, animated: false)
    }

    func configureSelectModeExtra() {
        if selectMode {
            navigationController?.navigationBar.tintColor = .lightGray
            navigationController?.navigationBar.isUserInteractionEnabled = false
            navigationController?.interactivePopGestureRecognizer?.isEnabled = false
        } else {
            selectionShareToolbarItem.image = UIImage(systemName: "eye")
            navigationController?.navigationBar.tintColor = .systemBlue
            navigationController?.navigationBar.isUserInteractionEnabled = true
            navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        }
    }

    @IBAction func selectButtonTapped(_ sender: UIButton) {
        selectMode.toggle()
    }

    @IBAction func selectionToolbarAction(_ sender: UIBarButtonItem) {
        guard let assetManager = assetManager, let selectedAssets = selectedAssets else {
            return
        }
        switch sender {
        case selectionShareToolbarItem:
            let unsharedAssets = selectedAssets.filter{ group.album.sharedAssets[$0.uuid] == nil }
            let selectedItems = collectionView.indexPathsForSelectedItems!
            if unsharedAssets.isNotEmpty {
                groupManager?.shareAssets(unsharedAssets, withGroup: group) { [weak self] success in
                    if success {
                        self?.view.makeToastie("Selected items are now visible to the rest of the group 🤳", duration: 6.0, position: .top)
                        for indexPath in selectedItems {
                            self?.collectionView.selectItem(at: indexPath, animated: false, scrollPosition: UICollectionView.ScrollPosition(rawValue: 0))
                            self?.selectCell(true, atIndexPath: indexPath)
                        }
                    } else {
                        self?.view.makeToastie("There was a problem sharing these items with the group", position: .top)
                    }
                    self?.shareToolbarButtonState()
                }
            } else {
                groupManager?.unshareAssets(selectedAssets, fromGroup: group) { [weak self] success in
                    if success {
                        self?.view.makeToastie("Selected items are no longer visible to the rest of the group 🤫", duration: 6.0, position: .top)
                        for indexPath in selectedItems {
                            self?.collectionView.selectItem(at: indexPath, animated: false, scrollPosition: UICollectionView.ScrollPosition(rawValue: 0))
                            self?.selectCell(true, atIndexPath: indexPath)
                        }
                    } else {
                        self?.view.makeToastie("There was a problem unsharing these items from the group", position: .top)
                    }
                    self?.shareToolbarButtonState()
                }
            }
        case selectionExportToolbarItem:
            export(assets: selectedAssets, assetRequester: assetManager, presentingViewController: self)
        case selectionSaveToolbarItem:
            save(assets: selectedAssets, assetService: assetManager, presentingViewController: self)
        case selectionDeleteToolbarItem:
            let ownedAssets = selectedAssets.filter{ $0.ownerID == primaryUserID }
            let unownedAssets = Set(selectedAssets).subtracting(ownedAssets)
            let deleteAction = UIAlertAction(title: ownedAssets.isNotEmpty ? "Delete" : "Delete for Me", style: .destructive) { _ in
                self.assetManager?.delete(selectedAssets)
                self.selectionBadgeCounter.value = 0
            }
            let cancelAction = UIAlertAction(title: "Cancel", style: .cancel) { _ in }
            let s = selectedAssets.count > 1 ? "s" : ""
            let deleteAlert = UIAlertController(title: nil, message: "\(selectedAssets.count) item\(s) selected", preferredStyle: .actionSheet)
            if ownedAssets.isNotEmpty {
                let removeAction = UIAlertAction(title: "Remove from Album", style: .destructive) { _ in
                    self.groupManager?.removeAssets(ownedAssets, from: self.group) { [weak self] success in
                        if success {
                            self?.selectionBadgeCounter.value = 0
                        } else {
                            self?.view.makeToastie("Error removing some items from album", position: .top)
                        }
                    }
                    self.assetManager?.delete(unownedAssets)
                    self.selectionBadgeCounter.value = self.selectionBadgeCounter.value - unownedAssets.count
                }
                deleteAlert.addAction(removeAction)
            }
            deleteAlert.addAction(deleteAction)
            deleteAlert.addAction(cancelAction)
            present(deleteAlert, animated: true)
        default:
            assertionFailure()
        }
    }

    @IBAction func longPressOnCollectionView(_ sender: UILongPressGestureRecognizer) {
        multiselect(with: sender)
    }

    private func shareToolbarButtonState() {
        if let selectedAssets = selectedAssets {
            let allShared = selectedAssets.allSatisfy{ group.album.sharedAssets[$0.uuid] != nil }
            selectionShareToolbarItem.image = allShared ? UIImage(systemName: "eye.slash") : UIImage(systemName: "eye")
        } else {
            selectionShareToolbarItem.image = UIImage(systemName: "eye")
        }
    }
}

extension PhotoView: AppContextObserver {
    func reload(inProgress: Bool) {
        if !inProgress, collectionView?.refreshControl?.isRefreshing == .some(true) {
            collectionView?.refreshControl?.endRefreshing()
        }
    }
}

extension PhotoView: GroupObserver {
    func deleted(_ group: Group) {
        guard group == self.group else { return }
        navigationController?.popToRootViewController(animated: true)
    }

    func updated(_ oldGroup: Group, to newGroup: Group) {
        guard oldGroup == self.group else { return }
        self.group = newGroup
        let newAssetIDs = Set(newGroup.album.pics.keys).subtracting(oldGroup.album.pics.keys)
        let deletedAssetIDs = Set(oldGroup.album.pics.keys).subtracting(newGroup.album.pics.keys)
        let mutualAssetIDs = Set(newGroup.album.pics.keys).intersection(oldGroup.album.pics.keys)

        if newAssetIDs.isNotEmpty {
            let newAssets = Set(newGroup.album.pics.filter{ newAssetIDs.contains($0.key) }.values)
            collectionViewDelegate.insert(newAssets, into: collectionView)
            fullscreenVC?.new(newAssets)
        }
        if deletedAssetIDs.isNotEmpty {
            let deletedAssets = Set(oldGroup.album.pics.filter{ deletedAssetIDs.contains($0.key) }.values)
            collectionViewDelegate.delete(deletedAssets, from: collectionView)
            fullscreenVC?.deleted(deletedAssets)
        }
        for assetID in mutualAssetIDs {
            let oldAsset = oldGroup.album.pics[assetID]!
            let newAsset = newGroup.album.pics[assetID]!
            if oldAsset != newAsset {
                collectionViewDelegate.update(oldAsset, with: newAsset, in: collectionView)
                fullscreenVC?.updated(oldAsset, to: newAsset)
            }
        }

        let sharedAssetsDiff = Set(oldGroup.album.sharedAssets.values).symmetricDifference(newGroup.album.sharedAssets.values).intersection(Set(newGroup.album.pics.values).intersection(oldGroup.album.pics.values))
        if sharedAssetsDiff.isNotEmpty {
            let sharedIndexPathDiffs = collectionViewDelegate.indexPaths(for: Array(sharedAssetsDiff))
            let indexPaths = Set(collectionView.indexPathsForVisibleItems).intersection(sharedIndexPathDiffs)
            collectionView.reloadItems(at: Array(indexPaths))
        }
    }
}

extension PhotoView: PurchasesObserver {
    func updated(storageTier: StorageTier) {
        if storageTier != .free {
            view.makeToastie("You're now subscribed to TripUp Pro! 👏", position: .center)
        }
    }
}

extension PhotoView: UserSelectionDelegate {
    func selected<T>(users: T?, callback: @escaping (UserSelectionDelegateResult) -> Void) where T: Collection, T.Element == User {
        guard let groupManager = groupManager, let users = users else { callback(.success); return }
        let newUsers = Set(users).subtracting(group.members)
        precondition(Set(group.members.map{ $0.uuid }).isDisjoint(with: newUsers.map{ $0.uuid }))
        guard newUsers.isNotEmpty else { callback(.success); return }
        groupManager.addUsers(newUsers, to: group) { success in
            if success {
                callback(.success)
            } else {
                callback(.failure("Failed to add trippers to the album. Try again in a moment."))
            }
        }
    }
}

extension PhotoView: FullscreenViewTransitionDelegate {
    func transitioning(from index: Int) -> (CGRect, UIImage?) {
        let indexPath = collectionViewDelegate.indexPath(forIndex: index)
        let cell = collectionView.cellForItem(at: indexPath) as! AlbumCollectionViewCell
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

// MARK: Gestures
extension PhotoView: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer == swipePhotoGesture && otherGestureRecognizer == collectionView.panGestureRecognizer {
            return true
        }
        return false
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer == swipePhotoGesture {
            let velocity = swipePhotoGesture.velocity(in: collectionView)
            return abs(velocity.x) > abs(velocity.y)
        }
        return true
    }

    /// action on photo
    @IBAction func drag(_ recognizer: UIPanGestureRecognizer) {
        let translation = recognizer.translation(in: self.view)

        switch recognizer.state {
        case .possible:
            break

        case .began:
            guard let indexPaths = indexes(for: recognizer) else { log.verbose("no index path(s) found"); return }
            selectedIndexesForGesture = indexPaths

            // animate cells moving with finger
            for indexPath in indexPaths {
                let cell = collectionView.cellForItem(at: indexPath) as? AlbumCollectionViewCell
                cell?.showActionIcon(share: translation.x > 0)
                cell?.assetContents.frame.origin.x = translation.x
            }

        case .changed:
            // animate cells moving with finger
            guard let indexPaths = selectedIndexesForGesture else { return }
            for indexPath in indexPaths {
                let cell = collectionView.cellForItem(at: indexPath) as? AlbumCollectionViewCell
                cell?.showActionIcon(share: translation.x > 0)
                cell?.assetContents.frame.origin.x = translation.x
            }

            // haptic feedback and action icon size change block
            if let swipeCellFeedback = swipeCellFeedback {
                guard abs(translation.x) <= swipeThresholdActivation else { return }
                swipeCellFeedback.selectionChanged()
                self.swipeCellFeedback = nil

                // reset action icon to size depending on asset state
                UIViewPropertyAnimator(duration: 0.5, dampingRatio: 0.5) {
                    let assets = self.collectionViewDelegate.items(at: indexPaths)
                    for (index, indexPath) in indexPaths.enumerated() {
                        let asset = assets[index]
                        let cell = self.collectionView.cellForItem(at: indexPath) as? AlbumCollectionViewCell
                        let shared = self.group.album.sharedAssets[asset.uuid] != nil
                        if asset.ownerID == self.primaryUserID {
                            cell?.shareActionIconConstraint.isZoomed = shared
                            cell?.unshareActionIconConstraint.isZoomed = !shared
                        } else {
                            cell?.shareActionIconConstraint.isZoomed = true
                            cell?.unshareActionIconConstraint.isZoomed = true
                        }
                        cell?.actionIconContents.layoutIfNeeded()
                    }
                }.startAnimation()
            } else {
                guard abs(translation.x) >= swipeThresholdActivation else { return }
                UIViewPropertyAnimator(duration: 0.5, dampingRatio: 0.5) {
                    for indexPath in indexPaths {
                        let cell = self.collectionView.cellForItem(at: indexPath) as? AlbumCollectionViewCell
                        if translation.x > 0 {  // greater than 0 = swipe to right, aka share. less than 0 = swipe to left, aka unshare
                            cell?.shareActionIconConstraint.isZoomed = true
                        } else {
                            cell?.unshareActionIconConstraint.isZoomed = true
                        }
                        cell?.actionIconContents.layoutIfNeeded()
                    }
                }.startAnimation()
                swipeCellFeedback = UISelectionFeedbackGenerator()
                swipeCellFeedback!.selectionChanged()
            }

        case .cancelled, .ended, .failed:
            guard let indexPaths = self.selectedIndexesForGesture else { return }
            defer {
                UIView.animate(withDuration: 0.2, animations: {
                    for indexPath in indexPaths {
                        let cell = self.collectionView.cellForItem(at: indexPath) as? AlbumCollectionViewCell
                        cell?.assetContents.frame.origin.x = self.collectionView.frame.origin.x
                    }
                }) { _ in
                    self.selectedIndexesForGesture = nil
                    self.swipeCellFeedback = nil
                }
            }

            // continue with action only if finger has moved past the activation threshold
            guard abs(translation.x) >= swipeThresholdActivation else { return }

            let selectedAssets = collectionViewDelegate.items(at: indexPaths)
            let toShare = translation.x > 0 // greater than 0 = swipe to right, aka share. less than 0 = swipe to left, aka unshare
            let assets = selectedAssets.filter{ ($0.ownerID == primaryUserID) && (toShare == (group.album.sharedAssets[$0.uuid] == nil)) }
            if assets.isNotEmpty {
                if toShare {
                    groupManager?.shareAssets(assets, withGroup: group) { [weak self] success in
                        if !success {
                            self?.view.makeToastie("There was a problem sharing photos", position: .top)
                        }
                    }
                    if group.members.isEmpty {
                        view.makeToastie("Add users to this album so they can see your shared photos", position: .center)
                    }
                } else {
                    groupManager?.unshareAssets(assets, fromGroup: group) { [weak self] success in
                        if !success {
                            self?.view.makeToastie("There was a problem unsharing photos", position: .top)
                        }
                    }
                }
            }
        @unknown default:
            fatalError()
        }
    }
}
