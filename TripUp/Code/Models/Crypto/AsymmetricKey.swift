//
//  AsymmetricKey.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 13/06/2019.
//  Copyright © 2019 Vinoth Ramiah. All rights reserved.
//

import Foundation

enum KeyConstructionError: Error {
    case invalidKeyString
    case invalidPasswordForKey
    case passwordRequiredForKey
    case publicKeyUsedAsPrivateKey
    case privateKeyUsedAsPublicKey
}

enum KeyMessageError: Error {
    case invalidSignature
    case incorrectKeyUsedToDecrypt
    case invalidLegacyPGPData
    case noData
}

enum KeyType {
    case generic
    case user
    case group
    case asset
}

protocol AsymmetricKey: Hashable {
    var type: KeyType { get }
    var data: Data { get }
    var fingerprint: String { get }
}

protocol AsymmetricPublicKey: AsymmetricKey {
    associatedtype PrivateKey: AsymmetricPrivateKey
    var `public`: String { get }

    init(key: String, for type: KeyType) throws
    func encrypt(_ string: String, signed signedBy: PrivateKey?) -> String
    func encrypt(fileAtURL url: URL, chunkSize: Int, outputFilename: String) -> URL?
}

protocol AsymmetricPrivateKey: AsymmetricPublicKey {
    associatedtype PublicKey: AsymmetricPublicKey
    var `private`: String { get }
    var password: String? { get }

    init(_ type: KeyType, password: String?)
    init(key: String, password: String?, for type: KeyType) throws
    func decrypt(_ cipher: String, signedBy: PublicKey?) throws -> String
    func decrypt(_ cipher: String, signedByOneOf potentialSignatories: [PublicKey]) throws -> (String, PublicKey)
    func decrypt(_ binary: Data) throws -> Data
    func decrypt(fileAtURL url: URL, chunkSize: Int) -> URL?
}
