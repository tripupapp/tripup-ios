//
//  MutableAsset.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 28/07/2020.
//  Copyright © 2020 Vinoth Ramiah. All rights reserved.
//

import Foundation
import struct AVFoundation.AVFileType
import struct CoreGraphics.CGSize

extension AssetManager {
    class MutableAsset: MutableAssetProtocol {
        struct PhysicalAssets {
            let original: MutablePhysicalAsset
            let low: MutablePhysicalAsset

            subscript(_ quality: Quality) -> MutablePhysicalAsset {
                switch quality {
                case .low:
                    return low
                case .original:
                    return original
                }
            }
        }

        var physicalAssets: PhysicalAssets!

        let uuid: UUID
        let ownerID: UUID
        let creationDate: Date?
        let location: TULocation?
        let pixelSize: CGSize

        var fingerprint: String? {
            get {
                return database?.fingerprint(for: self)
            }
            set {
                guard let newValue = newValue else {
                    preconditionFailure()
                }
                database?.save(fingerprint: newValue, for: self)
            }
        }

        var originalUTI: AVFileType? {
            get {
                return AVFileType(database?.uti(for: self))
            }
            set {
                guard let newValue = newValue else {
                    preconditionFailure()
                }
                database?.save(uti: newValue.rawValue, for: self)
            }
        }

        var localIdentifier: String? {
            get {
                return database?.localIdentifier(for: self)
            }
            set {
                database?.save(localIdentifier: newValue, for: self)
            }
        }

        var md5: Data? {
            get {
                return database?.md5(for: self)
            }
            set {
                guard let newValue = newValue else {
                    preconditionFailure()
                }
                database?.save(md5: newValue, for: self)
            }
        }

        var cloudFilesize: UInt64 {
            get {
                return database?.cloudFilesize(for: self) ?? 0
            }
            set {
                database?.save(cloudFilesize: newValue, for: self)
            }
        }

        var imported: Bool {
            get {
                return database?.importStatus(for: self) ?? false
            }
            set {
                database?.save(importStatus: newValue, for: self)
            }
        }

        var deleted: Bool {
            get {
                return database?.deleteStatus(for: self) ?? true
            }
            set {
                database?.save(deleteStatus: newValue, for: self)
            }
        }

        weak var database: MutableAssetDatabase? {
            didSet {
                physicalAssets.low.database = database
                physicalAssets.original.database = database
            }
        }

        private init(uuid: UUID, ownerID: UUID, creationDate: Date?, location: TULocation?, pixelSize: CGSize) {
            self.uuid = uuid
            self.ownerID = ownerID
            self.creationDate = creationDate
            self.location = location
            self.pixelSize = pixelSize
        }

        convenience init(from object: AssetObject) {
            self.init(
                uuid: UUID(uuidString: object.uuid)!,
                ownerID: UUID(uuidString: object.ownerID)!,
                creationDate: object.creationDate,
                location: TULocation(from: object),
                pixelSize: CGSize(width: object.pixelWidth, height: object.pixelHeight)
            )
            self.physicalAssets = PhysicalAssets(
                original: AssetManager.MutablePhysicalAsset(logicalAsset: self, quality: .original),
                low: AssetManager.MutablePhysicalAsset(logicalAsset: self, quality: .low)
            )
        }
    }
}
