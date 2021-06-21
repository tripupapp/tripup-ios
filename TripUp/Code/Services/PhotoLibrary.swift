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
    private let log = Logger.self

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
}

extension PhotoLibrary {
    func requestAVPlayerItem(forPHAsset phAsset: PHAsset, format: AssetManager.AVRequestFormat, callback: @escaping (AVPlayerItem?, AssetManager.ResultInfo?) -> Void) {
        let requestOptions = PHVideoRequestOptions()
        requestOptions.version = .current
        requestOptions.isNetworkAccessAllowed = true
        switch format {
        case .best:
            requestOptions.deliveryMode = .highQualityFormat
        case .fast:
            requestOptions.deliveryMode = .fastFormat
        case .opportunistic:
            requestOptions.deliveryMode = .automatic
        }

        PHImageManager.default().requestPlayerItem(forVideo: phAsset, options: requestOptions) { (avPlayerItem, info) in
            callback(avPlayerItem, AssetManager.ResultInfo(final: true, uti: nil))
        }
    }
}

extension PhotoLibrary {
    func write(resource: PHAssetResource, toURL url: URL, callback: @escaping ClosureBool) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)

        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        PHAssetResourceManager.default().writeData(for: resource, toFile: url, options: options) { (error) in
            if let error = error {
                self.log.error("error writing resource to disk - PHAssetID: \(resource.assetLocalIdentifier), error: \(String(describing: error))")
                callback(false)
            } else {
                callback(true)
            }
        }
    }

    func transcodeVideoToMP4(forPHAsset phAsset: PHAsset, callback: @escaping ((URL, AVFileType)?) -> Void) {
        let requestOptions = PHVideoRequestOptions()
        requestOptions.version = .current
        requestOptions.deliveryMode = .highQualityFormat
        requestOptions.isNetworkAccessAllowed = true
        PHImageManager.default().requestExportSession(forVideo: phAsset, options: requestOptions, exportPreset: AVAssetExportPresetPassthrough) { (exportSession, _) in
            guard let exportSession = exportSession else {
                callback(nil)
                return
            }
            let uti: AVFileType = .mp4
            guard let destinationURL = FileManager.default.createUniqueTempFile(filename: phAsset.localIdentifier, fileExtension: uti.fileExtension) else {
                callback(nil)
                return
            }
            exportSession.outputURL = destinationURL
            exportSession.outputFileType = uti
            exportSession.exportAsynchronously(completionHandler: { [unowned exportSession] in
                if case .completed = exportSession.status {
                    callback((destinationURL, uti))
                } else {
                    self.log.error("error transcoding video to MP4 - PHAssetID: \(phAsset.localIdentifier), outputURL: \(String(describing: exportSession.outputURL)), error: \(String(describing: exportSession.error))")
                    callback(nil)
                }
            })
        }
    }

    func compressVideo(atURL url: URL, callback: @escaping (URL?) -> Void) {
        let asset = AVAsset(url: url)
        let preset = AVAssetExportPresetLowQuality
        let uti: AVFileType = .mp4
        AVAssetExportSession.determineCompatibility(ofExportPreset: preset, with: asset, outputFileType: uti) { isCompatible in
            guard isCompatible else {
                self.log.error("export session incompatible - sourceURL: \(String(describing: url)), preset: \(preset), uti: \(String(describing: uti))")
                callback(nil)
                return
            }
            guard let exportSession = AVAssetExportSession(asset: asset, presetName: preset) else {
                callback(nil)
                return
            }
            guard let destinationURL = FileManager.default.createUniqueTempFile(filename: url.deletingPathExtension().lastPathComponent, fileExtension: uti.fileExtension ?? "") else {
                callback(nil)
                return
            }
            exportSession.outputURL = destinationURL
            exportSession.outputFileType = uti
            exportSession.exportAsynchronously(completionHandler: { [unowned exportSession] in
                if case .completed = exportSession.status {
                    callback(destinationURL)
                } else {
                    self.log.error("sourceURL: \(String(describing: url)), destinationURL: \(String(describing: destinationURL)) - error: \(String(describing: exportSession.error))")
                    callback(nil)
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
