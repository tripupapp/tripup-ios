//
//  FullscreenVC.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 27/05/2019.
//  Copyright © 2019 Vinoth Ramiah. All rights reserved.
//

import Foundation
import UIKit

protocol FullscreenViewTransitionDelegate {
    func transitioning(from index: Int) -> (CGRect, UIImage?)
    func transitioning(to index: Int) -> CGRect
}

protocol FullscreenViewDelegate: class {
    var modelCount: Int { get }
    var modelIsEmpty: Bool { get }
    var ownerLabel: UILabel? { get set }
    var bottomToolbarItems: [UIBarButtonItem]? { get }
    func fullsizeOfItem(at index: Int) -> CGSize
    func configure(cell: FullscreenViewCell, forItemAt index: Int)
    func configureOverlayViews(forItemAt index: Int)
    func prefetchItems(at indexes: [Int])
    func insert(_ newAssets: Set<Asset>) -> [IndexPath]
    func remove(_ deletedAssets: Set<Asset>) -> [IndexPath]
    func update(_ oldAsset: Asset, with newAsset: Asset) -> IndexPath
    func bottomToolbarAction(_ fullscreenVC: FullscreenViewController, button: UIBarButtonItem, itemIndex: Int)
}

class FullscreenViewController: UIViewController {
    @IBOutlet var collectionView: UICollectionView!
    @IBOutlet var presentingImageView: UIImageView!
    @IBOutlet var overlayViews: [UIView]!
    @IBOutlet var ownerLabel: UILabel!
    @IBOutlet var bottomToolbar: UIToolbar!

    var delegate: FullscreenViewDelegate!
    var onDismiss: (() -> Void)?
    private var initialIndex: Int!
    private var presenter: FullscreenViewTransitionDelegate?
    private var hideStatusBar: Bool = true {
        didSet {
            UIView.animate(withDuration: 0.2) {
                self.setNeedsStatusBarAppearanceUpdate()
            }
        }
    }

    func initialise(delegate: FullscreenViewDelegate, initialIndex: Int, presenter: FullscreenViewTransitionDelegate? = nil) {
        self.delegate = delegate
        self.initialIndex = initialIndex
        self.presenter = presenter

        self.modalPresentationStyle = .overFullScreen
        self.modalPresentationCapturesStatusBarAppearance = true
    }

    func assertDependencies() {
        assert(delegate != nil)
        assert(initialIndex != nil)
    }

    override var prefersStatusBarHidden: Bool {
        return hideStatusBar
    }

    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation {
        return .fade
    }

    override var prefersHomeIndicatorAutoHidden: Bool {
        return true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        assertDependencies()

        collectionView.dataSource = self
        collectionView.prefetchDataSource = self
        collectionView.delegate = self

        ownerLabel.layer.cornerRadius = 5.0
        ownerLabel.layer.masksToBounds = true
        delegate.ownerLabel = ownerLabel

        overlayViews.forEach{ $0.isHidden = false }
        overlayViews.forEach{ $0.alpha = 0.0 }

        if #available(iOS 13.0, *) {
            let toolbarAppearance = UIToolbarAppearance()
            toolbarAppearance.configureWithTransparentBackground()
            bottomToolbar.standardAppearance = toolbarAppearance
        } else {
            bottomToolbar.setBackgroundImage(UIImage(), forToolbarPosition: .any, barMetrics: .default)
            bottomToolbar.setShadowImage(UIImage(), forToolbarPosition: .any)
        }
        bottomToolbar.items = [UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)]
        if let bottomBarItems = delegate.bottomToolbarItems {
            for item in bottomBarItems {
                item.target = self
                item.action = #selector(bottomToolbarAction)
                bottomToolbar.items?.append(item)
                bottomToolbar.items?.append(UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil))
            }
        }

        if let presenter = presenter {
            let (frame, image) = presenter.transitioning(from: initialIndex)
            presentingImageView.frame = frame
            presentingImageView.image = image
            presentingImageView.isHidden = false
        } else {
            collectionView.isHidden = false
            view.backgroundColor = .black
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if view.safeAreaInsets.bottom == 0 {
            additionalSafeAreaInsets.top += 20
        }

        collectionView.scrollToItem(at: IndexPath(item: initialIndex, section: 0), at: .centeredHorizontally, animated: false)
        if presenter != nil {
            UIView.animate(withDuration: 0.2) {
                self.view.backgroundColor = .black
            }
            UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0, options: .curveEaseInOut, animations: {
                self.presentingImageView.frame = self.frame(forSize: self.delegate.fullsizeOfItem(at: self.initialIndex))
            }) { _ in
                UIView.animate(withDuration: 0.2) {
                    self.overlayViews.forEach{ $0.alpha = 1.0 }
                }
                self.presentingImageView.isHidden = true
                self.collectionView.isHidden = false
            }
        }
    }

    @IBAction func back(_ sender: UIButton) {
        let indexPath = collectionView.indexPathsForVisibleItems.first!
        let cell = collectionView.cellForItem(at: indexPath) as! FullscreenViewCell
        dismiss(indexPath: indexPath, withCell: cell)
    }

    @IBAction func panning(_ gesture: UIPanGestureRecognizer) {
        guard let indexPath = collectionView.indexPathForItem(at: gesture.location(in: collectionView)), let cell = collectionView.cellForItem(at: indexPath) as? FullscreenViewCell else { return }
        let translation = gesture.translation(in: view)
        switch gesture.state {
        case .possible:
            break
        case .began:
            _ = presenter?.transitioning(to: indexPath.item)
        case .changed:
            cell.contentView.center = CGPoint(x: view.center.x + translation.x, y: view.center.y + translation.y)
            if presenter != nil {
                overlayViews.forEach{ $0.isHidden = true }
                let percentage = translation.y / cell.frame.size.height
                if percentage < 1.0 {
                    self.view.backgroundColor = UIColor(white: 0, alpha: 1.0 - percentage)
                }
            }
        case .cancelled, .ended, .failed:
            if cell.contentView.center.y > view.center.y {
                dismiss(indexPath: indexPath, withCell: cell)
            } else {
                UIView.animate(withDuration: 0.2, animations: {
                    cell.contentView.center = self.view.center
                    self.view.backgroundColor = .black
                }) { _ in
                    self.overlayViews.forEach{ $0.isHidden = false }
                }
            }
        @unknown default:
            fatalError()
        }
    }

    @IBAction func toggleOverlay(_ sender: Any) {
        UIView.animate(withDuration: 0.3) {
            if let alpha: CGFloat = self.overlayViews.first?.alpha == 1.0 ? 0.0 : 1.0 {
                self.overlayViews.forEach{ $0.alpha = alpha }
            }
        }
    }

    @objc func bottomToolbarAction(_ sender: UIBarButtonItem) {
        let indexPath = collectionView.indexPathsForVisibleItems.first!
        delegate.bottomToolbarAction(self, button: sender, itemIndex: indexPath.item)
    }

    func new(_ assets: Set<Asset>) {
        let indexPaths = delegate.insert(assets)
        collectionView.performBatchUpdates({
            collectionView.insertItems(at: indexPaths)
        }) { [weak self] success in
            if success, let self = self, self.delegate.modelIsEmpty {
                self.dismiss(animated: true, completion: nil)
            }
        }
    }

    func deleted(_ assets: Set<Asset>) {
        let indexPaths = delegate.remove(assets)
        collectionView.performBatchUpdates({
            collectionView.deleteItems(at: indexPaths)
        }) { [weak self] success in
            if success, let self = self, self.delegate.modelIsEmpty {
                self.dismiss(animated: true, completion: nil)
            }
        }
    }

    func updated(_ oldAsset: Asset, to newAsset: Asset) {
        let indexPath = delegate.update(oldAsset, with: newAsset)
        collectionView.performBatchUpdates({
            collectionView.moveItem(at: indexPath, to: indexPath)
        }) { [weak self] success in
            if success, let self = self, self.delegate.modelIsEmpty {
                self.dismiss(animated: true, completion: nil)
            }
        }
    }

    private func dismiss(indexPath: IndexPath, withCell cell: FullscreenViewCell) {
        hideStatusBar = false
        if let presenter = presenter {
            let targetFrame = presenter.transitioning(to: indexPath.item)
            presentingImageView.frame = frame(forSize: delegate.fullsizeOfItem(at: indexPath.item))
            presentingImageView.center = cell.contentView.center
            presentingImageView.image = cell.imageView.image
            presentingImageView.isHidden = false
            collectionView.isHidden = true
            overlayViews.forEach{ $0.isHidden = true }
            UIView.animate(withDuration: 0.2, animations: {
                self.view.backgroundColor = .clear
                self.presentingImageView.frame = targetFrame
            }) { _ in
                UIView.animate(withDuration: 0.2, animations: {
                    self.presentingImageView.alpha = 0
                }, completion: { _ in
                    self.dismiss(animated: false, completion: self.onDismiss)
                })
            }
        } else {
            self.dismiss(animated: false, completion: onDismiss)
        }
    }

    private func frame(forSize itemSize: CGSize, within screenBounds: CGRect = UIScreen.main.bounds) -> CGRect {
        let widthScaleFactor = itemSize.width / screenBounds.size.width
        let heightScaleFactor = itemSize.height / screenBounds.size.height
        var centeredFrame = CGRect.zero

        let shouldFitHorizontally = widthScaleFactor > heightScaleFactor
        if shouldFitHorizontally && widthScaleFactor > 0 {
            let y = (screenBounds.size.height / 2) - ((itemSize.height / widthScaleFactor) / 2)
            centeredFrame = CGRect(x: 0, y: y, width: screenBounds.size.width, height: itemSize.height / widthScaleFactor)
        } else if heightScaleFactor > 0 {
            let x = (screenBounds.size.width / 2) - ((itemSize.width / heightScaleFactor) / 2)
            centeredFrame = CGRect(x: x, y: 0, width: screenBounds.size.width - (2 * x), height: screenBounds.size.height)
        }
        return centeredFrame
    }
}

extension FullscreenViewController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return delegate.modelCount
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: FullscreenViewCell.reuseIdentifier, for: indexPath) as! FullscreenViewCell
        cell.scrollView.decelerationRate = .fast
        cell.zoomOccurred = { [weak self] in
            UIView.animate(withDuration: 0.3) {
                self?.overlayViews.forEach{ $0.alpha = 0.0 }
            }
        }
        delegate.configure(cell: cell, forItemAt: indexPath.item)
        return cell
    }

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }
}

extension FullscreenViewController: UICollectionViewDataSourcePrefetching {
    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        delegate.prefetchItems(at: indexPaths.map{ $0.item })
    }
}

extension FullscreenViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        delegate.configureOverlayViews(forItemAt: indexPath.item)
    }

    func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        let cell = cell as! FullscreenViewCell
        cell.scrollView.zoomScale = 1.0
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        let center = CGPoint(x: scrollView.contentOffset.x + (scrollView.frame.width / 2), y: (scrollView.frame.height / 2))
        if let indexPath = collectionView.indexPathForItem(at: center) {
            delegate.configureOverlayViews(forItemAt: indexPath.item)
        }
    }
}

extension FullscreenViewController: UICollectionViewDelegateFlowLayout {
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        return collectionView.frame.size
    }
}

extension FullscreenViewController: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if let imagePanGesture = gestureRecognizer as? UIPanGestureRecognizer {
            let velocity = imagePanGesture.velocity(in: collectionView)
            return abs(velocity.y) > abs(velocity.x)    // only vertical pan
        }
        return true
    }
}