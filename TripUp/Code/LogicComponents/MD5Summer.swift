//
//  MD5Summer.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 08/07/2021.
//  Copyright © 2021 Vinoth Ramiah. All rights reserved.
//

import Foundation
import CommonCrypto

class MD5Summer {
    var result: Result<Data, Error>?
    var hexDigest: String? {
        if case .success(let data) = result {
            return data.map { String(format: "%02x", $0) }.joined()
        } else {
            return nil
        }
    }
    private var context: CC_MD5_CTX

    init() {
        context = CC_MD5_CTX()
        CC_MD5_Init(&context)
    }

    func input(_ data: Data) {
        guard data.count > 0 else {
            return
        }
        data.withUnsafeBytes {
            _ = CC_MD5_Update(&context, $0.baseAddress, numericCast(data.count))
        }
    }

    func abort(_ error: Error) {
        result = .failure(error)
    }

    func finalise() {
        var digest: [UInt8] = Array(repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        _ = CC_MD5_Final(&digest, &context)
        result = .success(Data(digest))
    }
}
