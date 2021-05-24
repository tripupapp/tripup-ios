//
//  Data.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 17/03/2019.
//  Copyright © 2019 Vinoth Ramiah. All rights reserved.
//

import Foundation
import CommonCrypto
import ImageIO
import MobileCoreServices

extension Data {
    /*
        https://nshipster.com/image-resizing/#cgimagesourcecreatethumbnailatindex
        https://developer.apple.com/videos/play/wwdc2018/219/
     */
    func downsample(to size: CGSize, scale: CGFloat, compress: Bool) -> Data? {
        let imageSourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary     // don't decode image yet, just create CGImageSource that represents the data
        guard let imageSource = CGImageSourceCreateWithData(self as CFData, imageSourceOptions) else { return nil }

        let thumbnailOptions = [
            kCGImageSourceThumbnailMaxPixelSize: Swift.max(size.width, size.height) * scale,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true      // when creating thumbnail, at that exact moment, create the decoded image buffer
        ] as CFDictionary
        guard let scaledImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, thumbnailOptions as CFDictionary) else {
            fatalError("unable to create thumbnail image")
        }

        let data = NSMutableData()
        guard let imageDestination = CGImageDestinationCreateWithData(data, kUTTypeJPEG, 1, nil) else {
            fatalError("unable to create image destination")
        }
        let imageDestinationOptions = compress ? [kCGImageDestinationLossyCompressionQuality as String: 0.0] as CFDictionary : nil  // maximum compression, if compression is used
        CGImageDestinationAddImage(imageDestination, scaledImage, imageDestinationOptions)
        guard CGImageDestinationFinalize(imageDestination) else {
            fatalError("something went wrong with downsampling")
        }
        return data as Data
    }
}

extension Data {
    func md5() -> Data {
        let hash = self.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) -> [UInt8] in
            var hash = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
            CC_MD5(bytes.baseAddress, CC_LONG(self.count), &hash)
            return hash
        }
        return Data(hash)
    }
}
