//
//  MutablePhysicalAsset.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 28/07/2020.
//  Copyright © 2020 Vinoth Ramiah. All rights reserved.
//

import Foundation
import struct CoreGraphics.CGSize

extension AssetManager {
    class MutablePhysicalAsset: MutableAssetProtocol {
        unowned let logicalAsset: MutableAsset
        let quality: Quality

        var remotePath: URL? {
            get {
                return database?.remotePath(for: self)
            }
            set {
                database?.save(remotePath: newValue, for: self)
            }
        }

        weak var database: MutableAssetDatabase?

        var uuid: UUID {
            return logicalAsset.uuid
        }
        var pixelSize: CGSize {
            return logicalAsset.pixelSize
        }
        var filename: URL {
            let url = URL(string: uuid.string)!
            return url.appendingPathExtension(logicalAsset.originalUTI?.fileExtension ?? "")
        }
        var localPath: URL {
            let filePath = "\(logicalAsset.ownerID.string)/\(filename.absoluteString)"
            switch quality {
            case .low:
                return Globals.Directories.assetsLow.appendingPathComponent(filePath, isDirectory: false)
            case .original:
                return Globals.Directories.assetsOriginal.appendingPathComponent(filePath, isDirectory: false)
            }
        }

        init(logicalAsset: MutableAsset, quality: Quality) {
            self.logicalAsset = logicalAsset
            self.quality = quality
        }
    }
}
