//
//  PHAssetResourceType.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 25/08/2021.
//  Copyright © 2021 Vinoth Ramiah. All rights reserved.
//

import Foundation
import enum Photos.PhotosTypes.PHAssetResourceType

extension PHAssetResourceType {
    init?(_ asset: Asset) {
        switch asset.type {
        case .photo:
            self.init(rawValue: PHAssetResourceType.photo.rawValue)
        case .video:
            self.init(rawValue: PHAssetResourceType.video.rawValue)
        case .audio:
            self.init(rawValue: PHAssetResourceType.audio.rawValue)
        case .unknown:
            return nil
        }
    }
}
