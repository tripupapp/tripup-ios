//
//  Photos.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 25/08/2020.
//  Copyright © 2020 Vinoth Ramiah. All rights reserved.
//

import Foundation
import Photos

class PhotoLibary: NSObject {
    private let fetchOptions: PHFetchOptions = {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: #keyPath(PHAsset.creationDate), ascending: true)]
        return options
    }()

    var canAccess: Bool? {
        let status = PHPhotoLibrary.authorizationStatus()
        if status == .notDetermined {
            return nil
        }
        return status == .authorized
    }

    func requestAccess(callback: @escaping ClosureBool) {
        PHPhotoLibrary.requestAuthorization { (status) in
            DispatchQueue.main.async {
                callback(status == .authorized)
            }
        }
    }

    func fetchAsset(withLocalIdentifier localIdentifier: String, callbackOn dispatchQueue: DispatchQueue = .main, callback: @escaping (PHAsset?) -> Void) {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: fetchOptions)
        dispatchQueue.async {
            callback(result.firstObject)
        }
    }

    func fetchAssets(withLocalIdentifiers localIdentifiers: [String], callback: @escaping ([PHAsset]) -> Void) {
        DispatchQueue.global().async {
            let result = PHAsset.fetchAssets(withLocalIdentifiers: localIdentifiers, options: self.fetchOptions)
            var assets = [PHAsset]()
            assets.reserveCapacity(result.count)
            result.enumerateObjects { (asset, _, _) in
                assets.append(asset)
            }
            DispatchQueue.main.async {
                callback(assets)
            }
        }
    }

    func fetchAllAssets(callback: @escaping ([PHAsset], [String]) -> Void) {
        DispatchQueue.global().async {
            let fetchResult = PHAsset.fetchAssets(with: .image, options: self.fetchOptions)
            var assets = [PHAsset]()
            assets.reserveCapacity(fetchResult.count)
            var localIDs = [String]()
            localIDs.reserveCapacity(fetchResult.count)
            fetchResult.enumerateObjects { (asset, _, _) in
                assets.append(asset)
                localIDs.append(asset.localIdentifier)
            }
            DispatchQueue.main.async {
                callback(assets, localIDs)
            }
        }
    }
}

//extension PhotoLibary: PHPhotoLibraryChangeObserver {
//    func photoLibraryDidChange(_ changeInstance: PHChange) {
//        queue.async(flags: .barrier) { [weak self] in
//            guard let fetchResult = self?.fetchResult else { return }
//            guard let changes = changeInstance.changeDetails(for: fetchResult) else { return }
//            self?.fetchResult = changes.fetchResultAfterChanges
//        }
//    }
//}
