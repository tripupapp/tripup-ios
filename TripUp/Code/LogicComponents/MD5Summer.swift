//
//  MD5Summer.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 08/07/2021.
//  Copyright © 2021 Vinoth Ramiah. All rights reserved.
//

import Foundation
import CommonCrypto

// NOTE: workaround to address MD5 deprecated warnings in Xcode. See: https://stackoverflow.com/a/45743766

private protocol MD5SummerProtocol {
    func initialize()
    func input(_ data: Data)
    func finalise()
}

class MD5Summer {
    var result: Result<Data, Error>? {
        return md5SummerInternal.result
    }

    var hexDigest: String? {
        return md5SummerInternal.hexDigest
    }

    private let md5SummerInternal = MD5SummerInternal()

    init() {
        (md5SummerInternal as MD5SummerProtocol).initialize()
    }

    func input(_ data: Data) {
        (md5SummerInternal as MD5SummerProtocol).input(data)
    }

    func abort(_ error: Error) {
        md5SummerInternal.abort(error)
    }

    func finalise() {
        (md5SummerInternal as MD5SummerProtocol).finalise()
    }
}

fileprivate class MD5SummerInternal {
    var result: Result<Data, Error>?
    var hexDigest: String? {
        if case .success(let data) = result {
            return data.map { String(format: "%02x", $0) }.joined()
        } else {
            return nil
        }
    }
    private var context: CC_MD5_CTX?

    @available(iOS, deprecated: 13.0)
    func initialize() {
        context = CC_MD5_CTX()
        CC_MD5_Init(&context!)
    }

    @available(iOS, deprecated: 13.0)
    func input(_ data: Data) {
        guard data.count > 0 else {
            return
        }
        data.withUnsafeBytes {
            _ = CC_MD5_Update(&context!, $0.baseAddress, numericCast(data.count))
        }
    }

    func abort(_ error: Error) {
        result = .failure(error)
    }

    @available(iOS, deprecated: 13.0)
    func finalise() {
        var digest: [UInt8] = Array(repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        _ = CC_MD5_Final(&digest, &context!)
        result = .success(Data(digest))
    }
}

extension MD5SummerInternal: MD5SummerProtocol {}
