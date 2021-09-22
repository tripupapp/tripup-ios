//
//  CollectionViewMultiSelect.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 17/09/2021.
//  Copyright © 2021 Vinoth Ramiah. All rights reserved.
//

import Foundation
import UIKit

protocol CollectionViewMultiSelect: UIViewController {
    var collectionView: UICollectionView! { get set }
    var selectButton: UIButton! { get set }
    var selectionBadgeCounter: BadgeCounter { get }

    var collectionViewDelegate: CollectionViewDelegate! { get set }
    var selectedAssets: [Asset]? { get }
    var selectMode: Bool { get set }

    var lastLongPressedIndexPath: IndexPath? { get set }
    var scrollingAnimator: UIViewPropertyAnimator? { get set }
    var multiselectScrollingDown: Bool? { get set }

    func enterSelectMode(_ selectMode: Bool)
    func selectCell(_ select: Bool, atIndexPath indexPath: IndexPath)
    func hideSelectionToolbar(_ hide: Bool)
    func hideOtherBottomBars(_ hide: Bool)

    func multiselect(with longPressGesture: UILongPressGestureRecognizer)
}

extension CollectionViewMultiSelect {
    var selectedAssets: [Asset]? {
        guard let indexPaths = collectionView.indexPathsForSelectedItems, indexPaths.isNotEmpty else {
            return nil
        }
        let assets = collectionViewDelegate.items(at: indexPaths)
        return assets.isNotEmpty ? assets : nil
    }

    func enterSelectMode(_ selectMode: Bool) {
        if !selectMode {
            selectButton.setTitle("Select", for: .normal)
            collectionView.indexPathsForSelectedItems?.forEach {
                collectionView.deselectItem(at: $0, animated: false)
                (collectionView.cellForItem(at: $0) as? CollectionViewCell)?.deselect()
            }
            selectionBadgeCounter.value = 0
            hideSelectionToolbar(true)
            hideOtherBottomBars(false)
        } else {
            selectButton.setTitle("Cancel", for: .normal)
            hideSelectionToolbar(false)
            hideOtherBottomBars(true)
        }
    }

    func selectCell(_ select: Bool, atIndexPath indexPath: IndexPath) {
        let cell = collectionView.cellForItem(at: indexPath) as? CollectionViewCell
        if select {
            cell?.select()
        } else {
            cell?.deselect()
        }
        selectionBadgeCounter.value = collectionView.indexPathsForSelectedItems?.count ?? 0
    }

    func hideOtherBottomBars(_ hide: Bool) {}
}

extension CollectionViewMultiSelect {
    func multiselect(with longPressGesture: UILongPressGestureRecognizer) {
        switch longPressGesture.state {
        case .possible:
            break
        case .began:
            if !selectMode {
                selectMode.toggle()
                UISelectionFeedbackGenerator().selectionChanged()
            }
        case .changed:
            let locationOnScreen = longPressGesture.location(in: view)
            let tabBarHeight = tabBarController?.tabBar.frame.height ?? 0
            let cellHeight = collectionView.visibleCells.first?.frame.height ?? 0

            scrollingAnimator?.stopAnimation(true)
            if locationOnScreen.y < cellHeight {
                scroll(up: true)
            } else if locationOnScreen.y >= collectionView.frame.height - tabBarHeight - cellHeight {
                scroll(up: false)
            }

            let location = longPressGesture.location(in: collectionView)
            guard let indexPath = collectionView.indexPathForItem(at: location) else {
                return
            }
            guard lastLongPressedIndexPath != indexPath else {
                return
            }
            if let lastLongPressedIndexPath = lastLongPressedIndexPath {
                let sortedIndexPaths = collectionView.indexPathsForVisibleItems.sorted()
                let previousIndex = sortedIndexPaths.firstIndex(of: lastLongPressedIndexPath)
                let currentIndex = sortedIndexPaths.firstIndex(of: indexPath)
                if let previousIndex = previousIndex, let currentIndex = currentIndex {
                    let indexPathsToSelect: ArraySlice<IndexPath>
                    let scrollingDown: Bool
                    if previousIndex < currentIndex {
                        indexPathsToSelect = sortedIndexPaths[previousIndex ... currentIndex]
                        if multiselectScrollingDown == nil {
                            multiselectScrollingDown = true
                        }
                        scrollingDown = true
                    } else {
                        indexPathsToSelect = sortedIndexPaths[currentIndex ... previousIndex]
                        if multiselectScrollingDown == nil {
                            multiselectScrollingDown = false
                        }
                        scrollingDown = false
                    }
                    for indexPath in indexPathsToSelect {
                        if scrollingDown == multiselectScrollingDown {
                            collectionView.selectItem(at: indexPath, animated: true, scrollPosition: UICollectionView.ScrollPosition(rawValue: 0))
                            selectCell(true, atIndexPath: indexPath)
                        } else {
                            collectionView.deselectItem(at: indexPath, animated: true)
                            selectCell(false, atIndexPath: indexPath)
                        }
                    }
                }
            } else {
                collectionView.selectItem(at: indexPath, animated: false, scrollPosition: UICollectionView.ScrollPosition(rawValue: 0))
                selectCell(true, atIndexPath: indexPath)
            }
            lastLongPressedIndexPath = indexPath
        case .ended, .failed, .cancelled:
            scrollingAnimator?.stopAnimation(true)
            lastLongPressedIndexPath = nil
            multiselectScrollingDown = nil
        @unknown default:
            fatalError()
        }
    }

    private func scroll(up scrollUp: Bool) {
        scrollingAnimator = UIViewPropertyAnimator(duration: 0.25, curve: .linear, animations: { [weak self] in
            guard let self = self else {
                return
            }
            let yOffset = self.collectionView.contentOffset.y
            let contentHeight = self.collectionView.contentSize.height
            if scrollUp {
                self.collectionView.contentOffset.y = max(yOffset - 100, 0)
            } else if self.collectionView.frame.height + yOffset < contentHeight + 50 {
                self.collectionView.contentOffset.y = min(yOffset + 100, contentHeight)
            }
        })
        scrollingAnimator?.addCompletion({ [weak self] _ in
            self?.scroll(up: scrollUp)
        })
        scrollingAnimator?.startAnimation()
    }
}
