//
//  PhotoLibrary.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 25/08/2020.
//  Copyright © 2020 Vinoth Ramiah. All rights reserved.
//

import Foundation
import Photos

class PhotoLibrary: NSObject {
    private let fetchOptions: PHFetchOptions = {
        let options = PHFetchOptions()
        // only allow photos and videos; filter out audio and other types for now
        options.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
            NSPredicate(format: "%K == %d", #keyPath(PHAsset.mediaType), PHAssetMediaType.image.rawValue),
            NSPredicate(format: "%K == %d", #keyPath(PHAsset.mediaType), PHAssetMediaType.video.rawValue)
        ])
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
}

extension PhotoLibrary {
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
            let fetchResult = PHAsset.fetchAssets(with: self.fetchOptions)
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

    func resource(forPHAsset phAsset: PHAsset, type: AssetType) -> PHAssetResource? {
        let resourceType: PHAssetResourceType
        switch type {
        case .photo:
            resourceType = .fullSizePhoto
        case .video:
            resourceType = .fullSizeVideo
        case .audio:
            resourceType = .audio
        case .unknown:
            assertionFailure()
            return nil
        }
        let resources = PHAssetResource.assetResources(for: phAsset)
        return resources.first(where: { $0.type == resourceType })
    }

    func write(resource: PHAssetResource, toURL url: URL, callback: @escaping ClosureBool) {
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        PHAssetResourceManager.default().writeData(for: resource, toFile: url, options: options) { (error) in
            if let _ = error {
                callback(false)
            } else {
                callback(true)
            }
        }
    }

    func exportVideoData(forIOSAsset iosAsset: PHAsset, toURL url: URL, callback: @escaping (Bool, AVFileType?) -> Void) {
        let requestOptions = PHVideoRequestOptions()
        requestOptions.version = .current
        requestOptions.deliveryMode = .highQualityFormat
        requestOptions.isNetworkAccessAllowed = true

        iosImageManager.requestExportSession(forVideo: iosAsset, options: requestOptions, exportPreset: AVAssetExportPresetPassthrough) { [weak self] (exportSession, _) in
            guard let exportSession = exportSession else {
                callback(false, nil)
                return
            }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
            let uti: AVFileType = .mp4
            exportSession.outputURL = url
            exportSession.outputFileType = uti
            exportSession.exportAsynchronously(completionHandler: { [unowned exportSession] in
                if case .completed = exportSession.status {
                    callback(true, uti)
                } else {
                    self?.log.error("phassetid: \(iosAsset.localIdentifier) - error: \(String(describing: exportSession.error))")
                    callback(false, uti)
                }
            })
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
