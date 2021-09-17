//
//  CollectionViewMultiSelect.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 17/09/2021.
//  Copyright © 2021 Vinoth Ramiah. All rights reserved.
//

import Foundation
import UIKit

protocol CollectionViewMultiSelect {
    var collectionView: UICollectionView! { get set }
    var selectButton: UIButton! { get set }
    var selectionToolbar: UIToolbar! { get set }
    var selectionBadgeCounter: BadgeCounter { get }

    var collectionViewDelegate: CollectionViewDelegate! { get set }
    var selectedAssets: [Asset]? { get }
    var selectMode: Bool { get set }

    func enterSelectMode(_ selectMode: Bool)
    func selectCell(_ select: Bool, atIndexPath indexPath: IndexPath)
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
                if let cell = collectionView.cellForItem(at: $0) as? CollectionViewCell {
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

    func selectCell(_ select: Bool, atIndexPath indexPath: IndexPath) {
        let cell = collectionView.cellForItem(at: indexPath) as? CollectionViewCell
        if select {
            cell?.select()
        } else {
            cell?.deselect()
        }
        selectionBadgeCounter.value = collectionView.indexPathsForSelectedItems?.count ?? 0
    }
}
