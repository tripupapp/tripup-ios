//
//  KeychainTests.swift
//  TripUpTests
//
//  Created by Vinoth Ramiah on 14/06/2019.
//  Copyright © 2019 Vinoth Ramiah. All rights reserved.
//

import Foundation
import XCTest
import CryptoSwift
@testable import TripUp

class KeychainTests: XCTestCase {
    private let keychain = Keychain<TestPublicKey, TestPrivateKey>(environment: .test)

    override func setUp() {
        super.setUp()
        let secClasses = [
            kSecClassGenericPassword,
            kSecClassKey
        ]
        for secClass in secClasses {
            let query: [CFString: Any] = [
                kSecClass: secClass,
                kSecAttrCreator: KeychainCreator.TRUP,
                kSecAttrLabel: KeychainEnvironment.test.rawValue
            ]
            SecItemDelete(query as CFDictionary)
        }
    }
}

// MARK: TestKey objects
extension KeychainTests {
    class TestPublicKey: AsymmetricPublicKey {
        static func == (lhs: TestPublicKey, rhs: TestPublicKey) -> Bool {
            return lhs.data == rhs.data
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(data)
            hasher.combine(type)
        }

        var data: Data {
            return self.public.data(using: .utf8)!
        }

        var fingerprint: String {
            return self.public.sha1()
        }

        let type: KeyType
        let `public`: String

        required init(key: String, for type: KeyType) throws {
            self.type = type
            self.public = key
        }

        func encrypt(_ string: String, signed signedBy: TestPrivateKey?) -> String {
            return string.data(using: .utf8)!.base64EncodedString()
        }

        func encrypt(_ binary: Data) -> Data {
            return binary.base64EncodedData()
        }
    }

    class TestPrivateKey: TestPublicKey, AsymmetricPrivateKey {
        override var data: Data {
            return self.private.data(using: .utf8)!
        }

        override var fingerprint: String {
            return self.private.sha1()
        }

        let `private`: String
        let password: String?

        required init(key: String, password: String?, for type: KeyType) throws {
            self.private = key
            self.password = password
            try super.init(key: key , for: type)
        }

        required convenience init(_ type: KeyType, password: String?) {
            try! self.init(key: UUID().string, password: password, for: type)
        }

        required init(key: String, for type: KeyType) throws {
            fatalError("This is a public key initializer")
        }

        func decrypt(_ cipher: String, signedByOneOf potentialSignatories: [KeychainTests.TestPublicKey]) throws -> (String, KeychainTests.TestPublicKey) {
            var result: String?
            var signature: KeychainTests.TestPublicKey?
            for potentialSignatory in potentialSignatories {
                do {
                    result = try decrypt(cipher, signedBy: potentialSignatory)
                    signature = potentialSignatory
                    break
                } catch KeyMessageError.invalidSignature { }
            }
            guard let plainText = result, let signingKey = signature else { throw KeyMessageError.invalidSignature }
            return (plainText, signingKey)
        }

        func decrypt(_ cipher: String, signedBy: TestPublicKey?) throws -> String {
            return String(data: Data(base64Encoded: cipher)!, encoding: .utf8)!
        }

        func decrypt(_ binary: Data) throws -> Data {
            return Data(base64Encoded: binary)!
        }
    }
}

// MARK: The actual tests
extension KeychainTests {
    func testCreatePublicKey() {
        let keyType = KeyType.user
        let key1 = try! TestPublicKey(key: "publicKey", for: keyType)
        var key2: TestPublicKey!
        XCTAssertNoThrow(key2 = try keychain.createPublicKey(for: keyType, from: "publicKey", saveToKeychain: false))
        XCTAssertEqual(key1, key2)
    }

    func testCreatePrivateKey() {
        let keyType = KeyType.asset
        let key1 = try! TestPrivateKey(key: "privateKey", password: nil, for: keyType)
        var key2: TestPrivateKey!
        XCTAssertNoThrow(key2 = try keychain.createPrivateKey(for: keyType, from: "privateKey", password: nil, saveToKeychain: false))
        XCTAssertEqual(key1, key2)
    }

    func testCreatePrivateKeyWithPass() {
        let keyType = KeyType.user
        let key1 = try! TestPrivateKey(key: "keyString", password: "keyPassword", for: keyType)
        var key2: TestPrivateKey!
        XCTAssertNoThrow(key2 = try keychain.createPrivateKey(for: keyType, from: "keyString", password: "keyPassword", saveToKeychain: false))
        XCTAssertEqual(key1, key2)
    }

    func testSaveSecret() {
        XCTAssertNoThrow(try keychain.save("testString", withLookupKey: "1234"))
    }

    func testSaveDuplicateSecret() {
        try! keychain.save("testString", withLookupKey: "1234")
        XCTAssertThrowsError(try keychain.save("testString", withLookupKey: "1234")) { errorThrown in
            guard let error = errorThrown as? KeychainError else { print(errorThrown); XCTFail(); return }
            XCTAssertEqual(error, KeychainError.duplicate(.password))
        }
    }

    func testSavePublicKey() {
        let key = try! TestPublicKey(key: "publicKey", for: .user)
        XCTAssertNoThrow(try keychain.savePublicKey(key))
    }

    func testSavePrivateKey() {
        let key = try! TestPrivateKey(key: "privateKey", password: nil, for: .asset)
        XCTAssertNoThrow(try keychain.savePrivateKey(key))
    }

    func testSavePrivateKeyWithPass() {
        let key = try! TestPrivateKey(key: "privateKeyWithPass", password: "keyPassword", for: .user)
        XCTAssertNoThrow(try keychain.savePrivateKey(key))
    }

    func testSaveDuplicateKeys() {
        let publicKey = try! TestPublicKey(key: "publicKey", for: .user)
        let privateKey = try! TestPrivateKey(key: "privateKey", password: nil, for: .asset)
        let privateKeyWithPass = try! TestPrivateKey(key: "privateKeyWithPass", password: "keyPassword", for: .user)
        try! keychain.savePublicKey(publicKey)
        try! keychain.savePrivateKey(privateKey)
        try! keychain.savePrivateKey(privateKeyWithPass)

        XCTAssertThrowsError(try keychain.savePublicKey(publicKey)) { errorThrown in
            guard let error = errorThrown as? KeychainError else { print(errorThrown); XCTFail(); return }
            XCTAssertEqual(error, KeychainError.duplicate(.key))
        }
        XCTAssertThrowsError(try keychain.savePrivateKey(privateKey)) { errorThrown in
            guard let error = errorThrown as? KeychainError else { print(errorThrown); XCTFail(); return }
            XCTAssertEqual(error, KeychainError.duplicate(.key))
        }
        XCTAssertThrowsError(try keychain.savePrivateKey(privateKeyWithPass)) { errorThrown in
            guard let error = errorThrown as? KeychainError else { print(errorThrown); XCTFail(); return }
            XCTAssertEqual(error, KeychainError.duplicate(.key))
        }
    }

    func testRetrieveSecret() {
        let secret = "testString"
        var returnVal: String?
        try! keychain.save(secret, withLookupKey: "1234")
        XCTAssertNoThrow(returnVal = try keychain.retrieveSecret(withLookupKey: "1234"))
        XCTAssertNotNil(returnVal)
        XCTAssertEqual(returnVal, secret)
    }

    func testRetrieveSecretFail() {
        var returnVal: String?
        XCTAssertNoThrow(returnVal = try keychain.retrieveSecret(withLookupKey: "1234"))
        XCTAssertNil(returnVal)
    }

    func testRetrievePublicKey() {
        let keyType = KeyType.user
        let publicKey = try! TestPublicKey(key: "publicKey", for: keyType)
        try! keychain.savePublicKey(publicKey)

        var returnedKey: TestPublicKey?
        XCTAssertNoThrow(returnedKey = try keychain.retrievePublicKey(withFingerprint: publicKey.fingerprint, keyType: keyType))
        XCTAssertNotNil(returnedKey)
        XCTAssertEqual(returnedKey, publicKey)
    }

    func testRetrievePrivateKey() {
        let keyType = KeyType.user
        let privateKey = try! TestPrivateKey(key: "privateKey", password: nil, for: keyType)
        try! keychain.savePrivateKey(privateKey)

        var returnedKey: TestPrivateKey?
        XCTAssertNoThrow(returnedKey = try keychain.retrievePrivateKey(withFingerprint: privateKey.fingerprint, keyType: keyType))
        XCTAssertNotNil(returnedKey)
        XCTAssertEqual(returnedKey, privateKey)
    }

    func testCreateSaveThenRetrieve() {
        let keyType = KeyType.asset
        let key1 = try! TestPrivateKey(key: "privateKey", password: nil, for: keyType)
        var key2: TestPrivateKey!
        XCTAssertNoThrow(key2 = try keychain.createPrivateKey(for: keyType, from: "privateKey", password: nil, saveToKeychain: true))
        XCTAssertEqual(key1, key2)

        var returnedKey: TestPrivateKey?
        XCTAssertNoThrow(returnedKey = try keychain.retrievePrivateKey(withFingerprint: key1.fingerprint, keyType: keyType))
        XCTAssertNotNil(returnedKey)
        XCTAssertEqual(returnedKey, key1)
    }

    func testDeleteSecret() {
        try! keychain.save("testString", withLookupKey: "1234")
        XCTAssertNoThrow(try keychain.deleteSecret(withLookupKey: "1234"))

        XCTAssertThrowsError(try keychain.deleteSecret(withLookupKey: "123")) { errorThrown in
            guard let error = errorThrown as? KeychainError else { print(errorThrown); XCTFail(); return }
            XCTAssertEqual(error, KeychainError.notFound(.password))
        }
    }

    func testDeletePublicKey() {
        let key = try! TestPublicKey(key: "publicKey", for: .user)
        try! keychain.savePublicKey(key)
        XCTAssertNoThrow(try keychain.deletePublicKey(key))
    }

    func testDeletePrivateKey() {
        let key = try! TestPrivateKey(key: "privateKey", password: nil, for: .asset)
        try! keychain.savePrivateKey(key)
        XCTAssertNoThrow(try keychain.deletePrivateKey(key))
    }

    func testDeletePrivateKeyWithPass() {
        let key = try! TestPrivateKey(key: "privateKey", password: "nil", for: .asset)
        try! keychain.savePrivateKey(key)
        XCTAssertNoThrow(try keychain.deletePrivateKey(key))
    }

    func testDeleteKeyNotFound() {
        let key1 = try! TestPublicKey(key: "publicKey", for: .user)
        let key2 = try! TestPrivateKey(key: "privateKey", password: nil, for: .asset)
        let key3 = try! TestPrivateKey(key: "privateKey", password: "nil", for: .asset)

        XCTAssertThrowsError(try keychain.deletePublicKey(key1)) { errorThrown in
            guard let error = errorThrown as? KeychainError else { print(errorThrown); XCTFail(); return }
            XCTAssertEqual(error, KeychainError.notFound(.key))
        }

        XCTAssertThrowsError(try keychain.deletePrivateKey(key2)) { errorThrown in
            guard let error = errorThrown as? KeychainError else { print(errorThrown); XCTFail(); return }
            XCTAssertEqual(error, KeychainError.notFound(.key))
        }

        XCTAssertThrowsError(try keychain.deletePrivateKey(key3)) { errorThrown in
            guard let error = errorThrown as? KeychainError else { print(errorThrown); XCTFail(); return }
            XCTAssertEqual(error, KeychainError.notFound(.key))
        }
    }
}
