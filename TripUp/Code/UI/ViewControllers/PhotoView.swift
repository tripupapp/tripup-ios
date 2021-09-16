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
    @IBOutlet var firstInstructionsLabel: UILabelIcon!
    @IBOutlet var collectionView: UICollectionView!
    @IBOutlet var swipePhotoGesture: UIPanGestureRecognizer!

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

    private var collectionViewDelegate: CollectionViewDelegate!
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

        collectionViewDelegate.cellConfiguration = { [unowned self] (cell: CollectionViewCell, asset: Asset) in
            let cell = cell as! AlbumCollectionViewCell
            let shared = self.group.album.sharedAssets[asset.uuid] != nil
            if #available(iOS 13.0, *), let image = UIImage(systemName: "eye") {
                cell.shareIcon.image = image
            }
            cell.shareIcon.isHidden = !shared

            if asset.ownerID == self.primaryUserID {
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
        }
        collectionViewDelegate.onSelection = { [unowned self] (collectionView: UICollectionView, dataModel: CollectionViewDataModel, selectedIndexPath: IndexPath) in
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
        }
        collectionViewDelegate.onCollectionViewUpdate = { [unowned self] in
            UIView.animate(withDuration: 0.25) {
                collectionView.alpha = self.collectionViewDelegate.collectionViewIsEmpty ? 0 : 1
            }
        }

        self.title = group.name
        let userAddImage: UIImage?
        if #available(iOS 13.0, *), let image = UIImage(systemName: "person.badge.plus.fill") {
            userAddImage = image
        } else {
            userAddImage = UIImage(named: "user-plus")
        }
        let userSelectionButton = UIBarButtonItem(image: userAddImage, style: .plain, target: self, action: #selector(PhotoView.loadUserSelection))
        self.navigationItem.leftItemsSupplementBackButton = true
        self.navigationItem.leftBarButtonItems = [userSelectionButton]
        let addFromIOSButton = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(PhotoView.photoPicker))
        self.navigationItem.rightBarButtonItems = [addFromIOSButton]

        let refreshControl = UIRefreshControl()
        collectionView.refreshControl = refreshControl
        refreshControl.addTarget(self, action: #selector(networkReload(_:)), for: .valueChanged)

        firstInstructionsLabel.textToReplace = "plus"
        if #available(iOS 13.0, *), let image = UIImage(systemName: "plus") {
            firstInstructionsLabel.replacementIcon = image.withRenderingMode(.alwaysTemplate)
        } else {
            firstInstructionsLabel.verticalOffset = 1.25
            firstInstructionsLabel.replacementIcon = UIImage(named: "ios-add")!
        }

//        if let child = children.first(where: { $0 is GuideBox }), let guideBoxVC = child as? GuideBox, UserDefaults.standard.bool(forKey: "\(group.uuid.string)–NewAlbum") {
//            guideBoxVC.removeFromPhotoView()
//            inAppGuideContainerView.removeFromSuperview()
//        }
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
