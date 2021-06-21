//
//  AVFileType.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 28/09/2019.
//  Copyright © 2019 Vinoth Ramiah. All rights reserved.
//

import Foundation
import MobileCoreServices.UTCoreTypes
import struct AVFoundation.AVFileType

extension AVFileType {
    init?(_ uti: String?) {
        guard let uti = uti else { return nil }
        self.init(uti)
    }
}

extension AVFileType {
    var fileExtension: String? {
        let utiCFString = self.rawValue as CFString
        return UTTypeCopyPreferredTagWithClass(utiCFString, kUTTagClassFilenameExtension)?.takeRetainedValue() as String?
    }
}

extension AVFileType {
    // https://developer.android.com/guide/topics/media/media-formats
    var isCrossCompatible: Bool {
        switch self {
        case .jpg, .heic, .heif:
            return true
        case .tif, .dng, .avci:
            return false
        case .mp4, .mobile3GPP:
            return true
        case .mobile3GPP2, .m4v, .mov:
            return false
        default:
            assertionFailure(self.rawValue)
            return false
        }
    }
}
