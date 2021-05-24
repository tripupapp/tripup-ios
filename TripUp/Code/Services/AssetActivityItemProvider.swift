//
//  AssetActivityItemProvider.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 26/03/2019.
//  Copyright © 2019 Vinoth Ramiah. All rights reserved.
//

import Foundation
import AVFoundation
import MobileCoreServices
import UIKit

class AssetActivityItemProvider: UIActivityItemProvider {
    private let asset: Asset
    private let assetDataRequester: AssetDataRequester
    private var semaphore: DispatchSemaphore?

    init(asset: Asset, assetDataRequester: AssetDataRequester) {
        self.asset = asset
        self.assetDataRequester = assetDataRequester
        super.init(placeholderItem: UIImage())
    }

    override var item: Any {
        var dataResult: Data?
        var uti: AVFileType?
        semaphore = DispatchSemaphore(value: 0)
        assetDataRequester.requestImageData(for: asset, format: .best) { [weak self] (imageData, resultInfo) in
            guard let self = self else { return }
            dataResult = imageData
            uti = resultInfo?.uti
            self.semaphore?.signal()
        }
        semaphore?.wait()

        semaphore = nil
        if let data = dataResult {
            let fileExtensionCFString = uti.map{ $0.rawValue as CFString }
            let fileExtension = fileExtensionCFString.map{ UTTypeCopyPreferredTagWithClass($0, kUTTagClassFilenameExtension)?.takeRetainedValue() } as? String ?? "jpg"
            let tempDir = Globals.Directories.tmp.appendingPathComponent("\(ProcessInfo().globallyUniqueString)", isDirectory: true)
            let tempURL = tempDir.appendingPathComponent("\(asset.uuid.string).\(fileExtension)", isDirectory: false)   // url last component used as filename of shared file
            do {
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
                try data.write(to: tempURL)
                return tempURL  // using URLs as UIImage/Data cause memory exhaustion when sharing 30+ photos
            } catch {
                Logger.self.error("error occurred writing to temp file \(tempURL.absoluteString)")
            }
        }

        return super.item
    }

    override func cancel() {
        semaphore?.signal()
        super.cancel()
    }
}
