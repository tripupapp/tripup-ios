//
//  Keychain.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 13/06/2019.
//  Copyright © 2019 Vinoth Ramiah. All rights reserved.
//

import Foundation

// FourCC converter: https://github.com/ubershmekel/fourcc-to-text

struct KeychainCreator {
    static let TRUP = 1414681936    // represents keys and secrets created, stored and managed by TripUp
    static let USER = 1431520594    // represents keys and secrets created, stored and managed by User, for example user key password stored in iCloud keychain
}

enum KeychainEnvironment: Int {
    case prod   =   1347571524  // PROD
    case debug  =   1145389639  // DEBG
    case test   =   1413829460  // TEST
}

enum KeychainItem {
    case key
    case password
}

enum KeychainError: Error, LocalizedError, Equatable {
    case unknownError(OSStatus)
    case unexpectedFormat
    case duplicate(KeychainItem)
    case invalidPasswordForKey
    case notFound(KeychainItem)

    init(for item: KeychainItem, with status: OSStatus) {
        switch status {
        case errSecDuplicateItem:
            self = .duplicate(item)
        case errSecItemNotFound:
            self = .notFound(item)
        default:
            self = .unknownError(status)
        }
    }
}

protocol KeychainProvider {
    associatedtype PublicKey: AsymmetricPublicKey
    associatedtype PrivateKey: AsymmetricPrivateKey

    func save(_ secret: String, withLookupKey key: String) throws
    func deleteSecret(withLookupKey lookupKey: String) throws
    func retrieveSecret(withLookupKey lookupKey: String) throws -> String?
    func generateNewPrivateKey(_ type: KeyType, passwordProtected: Bool, saveToKeychain: Bool) -> PrivateKey
    func createPublicKey(for type: KeyType, from key: String, saveToKeychain: Bool) throws -> PublicKey
    func createPrivateKey(for type: KeyType, from key: String, password: String?, saveToKeychain: Bool) throws -> PrivateKey
    func savePublicKey(_ publicKey: PublicKey) throws
    func savePrivateKey(_ privateKey: PrivateKey) throws
    func retrievePublicKey(withFingerprint fingerprint: String, keyType: KeyType) throws -> PublicKey?
    func retrievePrivateKey(withFingerprint fingerprint: String, keyType: KeyType) throws -> PrivateKey?
    func deletePublicKey(_ key: PublicKey) throws
    func deletePrivateKey(_ key: PrivateKey) throws
    func clear() throws
}

struct Keychain<PublicKey: AsymmetricPublicKey, PrivateKey: AsymmetricPrivateKey> {
    private let secretQueryBase: [CFString: Any]
    private let secretQueryBaseiCloud: [CFString: Any]
    private let keyQueryBase: [CFString: Any]
    private let keyDeleteQuery: [CFString: Any]
    private let environment: KeychainEnvironment

    init(environment: KeychainEnvironment) {
        self.secretQueryBase = [
            kSecClass:                  kSecClassGenericPassword,
            kSecAttrAccessible:         kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrCreator:            KeychainCreator.TRUP,
            kSecAttrLabel:              environment.rawValue,
            kSecAttrSynchronizable:     kCFBooleanFalse!
        ]
        self.secretQueryBaseiCloud = [
            kSecClass:                  kSecClassGenericPassword,
            kSecAttrCreator:            KeychainCreator.USER,
            kSecAttrLabel:              environment.rawValue,
            kSecAttrSynchronizable:     kCFBooleanTrue!,
        ]
        self.keyQueryBase = [
            kSecClass: kSecClassKey,
            kSecAttrAccessible:         kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrCreator:            KeychainCreator.TRUP,
            kSecAttrLabel:              environment.rawValue,
            kSecAttrKeyType:            kSecAttrKeyTypeECSECPrimeRandom,    // elliptic curve
            kSecAttrKeySizeInBits:      256,                                // x25519 = 256 bits
            kSecAttrEffectiveKeySize:   256,                                // 32 byte password = 32*8 = 256 bits
            kSecAttrIsPermanent:        true,                               // store in default keychain
            kSecAttrIsExtractable:      false,                              // item cannot be exported from keychain
            kSecAttrCanWrap:            false,                              // believe that officially, only symmetric keys can be used to wrap
            kSecAttrCanUnwrap:          false                               // believe that officially, only symmetric keys can be used to unwrap
        ]
        self.keyDeleteQuery = [
            kSecClass:          kSecClassKey,
            kSecAttrCreator:    KeychainCreator.TRUP,
            kSecAttrLabel:      environment.rawValue
        ]
        self.environment = environment
    }
}

// MARK: Keychain <-> iOS Keychain
extension Keychain {
    private func keyQueryBuilder(keyType: KeyType, privateKey: Bool, passwordProtected: Bool, fingerprint: String) -> [CFString: Any] {
        return keyQueryBase.merging([
            kSecAttrKeyClass:           privateKey ? kSecAttrKeyClassPrivate : kSecAttrKeyClassPublic,
            kSecAttrApplicationLabel:   fingerprint,    // public key hash - used as identifier for searching for the key
            kSecAttrApplicationTag:     "app.tripup.keys.\(keyType)".data(using: .utf8)!,

            kSecAttrIsSensitive:        privateKey && passwordProtected,    // key is not always encrypted/password protected (unprotected private key or public key)
            kSecAttrCanEncrypt:         !privateKey,
            kSecAttrCanDecrypt:         privateKey,
            kSecAttrCanDerive:          privateKey,
            kSecAttrCanSign:            privateKey,
            kSecAttrCanVerify:          !privateKey
        ]) { (_, new) in new }
    }

    private func save<T: AsymmetricKey>(_ key: T, privateKey: Bool, password: String? = nil) throws {
        let addQuery = keyQueryBuilder(keyType: key.type, privateKey: privateKey, passwordProtected: password != nil, fingerprint: key.fingerprint).merging([
            kSecValueData: key.data
        ]) { (_, new) in new }
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(for: .key, with: status) }
        if let password = password {
            try save(password, withLookupKey: key.fingerprint)
        }
    }

    private func deleteKey<T: AsymmetricKey>(_ key: T, privateKey: Bool, passwordProtected: Bool = false) throws {
        let query = keyQueryBuilder(keyType: key.type, privateKey: privateKey, passwordProtected: passwordProtected, fingerprint: key.fingerprint)
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess else { throw KeychainError(for: .key, with: status) }
    }

    private func retrieveKey(fingerprint: String, keyType: KeyType, privateKey: Bool, passwordProtected: Bool = false) throws -> String? {
        let query = keyQueryBuilder(keyType: keyType, privateKey: privateKey, passwordProtected: passwordProtected, fingerprint: fingerprint).merging([
            kSecMatchLimit:         kSecMatchLimitOne,
            kSecReturnAttributes:   false,
            kSecReturnData:         true
        ]) { (_, new) in new }
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status != errSecItemNotFound else { return nil }
        guard status == errSecSuccess else { throw KeychainError(for: .key, with: status) }
        guard let data = item as? Data, let keyString = String(data: data, encoding: .utf8) else { throw KeychainError.unexpectedFormat }
        return keyString
    }
}

// MARK: KeychainProvider functions
extension Keychain: KeychainProvider {
    func save(_ secret: String, withLookupKey key: String) throws {
        let addQuery = secretQueryBase.merging([
            kSecAttrAccount:    key,
            kSecValueData:      secret.data(using: .utf8)!
        ]) { (_, new) in new }
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(for: .password, with: status) }
    }

    func deleteSecret(withLookupKey lookupKey: String) throws {
        let query = secretQueryBase.merging([
            kSecAttrAccount: lookupKey
        ]) { (_, new) in new }
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess else { throw KeychainError(for: .password, with: status) }
    }

    func retrieveSecret(withLookupKey lookupKey: String) throws -> String? {
        let searchQuery = secretQueryBase.merging([
            kSecAttrAccount:        lookupKey,
            kSecMatchLimit:         kSecMatchLimitOne,
            kSecReturnAttributes:   false,
            kSecReturnData:         true
        ]) { (_, new) in new }
        var item: CFTypeRef?
        let status = SecItemCopyMatching(searchQuery as CFDictionary, &item)
        guard status != errSecItemNotFound else { return nil }
        guard status == errSecSuccess else { throw KeychainError(for: .password, with: status) }
        guard let data = item as? Data, let secret = String(data: data, encoding: .utf8) else { throw KeychainError.unexpectedFormat }
        return secret
    }

    func generateNewPrivateKey(_ type: KeyType, passwordProtected: Bool, saveToKeychain: Bool) -> PrivateKey {
        var password: String?
        if passwordProtected {
            var bytes = [UInt8](repeating: 0, count: 32)
            let result = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
            guard result == errSecSuccess else { fatalError("Unexpected result \(result) for SecRandomCopyBytes") }
            password = Data(bytes: &bytes, count: bytes.count).base64EncodedString()
        }
        let keypair = PrivateKey(type, password: password)
        if saveToKeychain {
            try! savePrivateKey(keypair)
        }
        return keypair
    }

    func createPublicKey(for type: KeyType, from key: String, saveToKeychain: Bool) throws -> PublicKey {
        let key = try PublicKey(key: key, for: type)
        if saveToKeychain {
            try savePublicKey(key)
        }
        return key
    }

    func createPrivateKey(for type: KeyType, from key: String, password: String?, saveToKeychain: Bool) throws -> PrivateKey {
        let keypair = try PrivateKey(key: key, password: password, for: type)
        if saveToKeychain {
            try savePrivateKey(keypair)
        }
        return keypair
    }

    func savePublicKey(_ publicKey: PublicKey) throws {
        try save(publicKey, privateKey: false)
    }

    func savePrivateKey(_ privateKey: PrivateKey) throws {
        try save(privateKey, privateKey: true, password: privateKey.password)
    }

    func retrievePublicKey(withFingerprint fingerprint: String, keyType: KeyType) throws -> PublicKey? {
        guard let keyString = try retrieveKey(fingerprint: fingerprint, keyType: keyType, privateKey: false) else {
            return nil
        }
        return try PublicKey(key: keyString, for: keyType)
    }

    func retrievePrivateKey(withFingerprint fingerprint: String, keyType: KeyType) throws -> PrivateKey? {
        let password = try retrieveSecret(withLookupKey: fingerprint)
        guard let keyString = try retrieveKey(fingerprint: fingerprint, keyType: keyType, privateKey: true, passwordProtected: password != nil) else {
            return nil
        }
        return try PrivateKey(key: keyString, password: password, for: keyType)
    }

    func deletePublicKey(_ key: PublicKey) throws {
        try deleteKey(key, privateKey: false)
    }

    func deletePrivateKey(_ key: PrivateKey) throws {
        var passwordProtected: Bool
        do {
            try deleteSecret(withLookupKey: key.fingerprint)
            passwordProtected = true
        } catch KeychainError.notFound(.password) {
            passwordProtected = false
        }
        try deleteKey(key, privateKey: true, passwordProtected: passwordProtected)
    }

    func clear() throws {
        let secretDeleteStatus = SecItemDelete(secretQueryBase as CFDictionary)
        guard secretDeleteStatus == errSecSuccess || secretDeleteStatus == errSecItemNotFound else { throw KeychainError(for: .password, with: secretDeleteStatus) }

        let keyDeleteStatus = SecItemDelete(keyDeleteQuery as CFDictionary)
        guard keyDeleteStatus == errSecSuccess || keyDeleteStatus == errSecItemNotFound else { throw KeychainError(for: .key, with: keyDeleteStatus) }
    }
}

// MARK: iCloud Keychain
extension Keychain {
    func saveToiCloud(_ password: String, lookupKey: String) throws {
        let addQuery = secretQueryBaseiCloud.merging([
            kSecAttrAccessible:     kSecAttrAccessibleWhenUnlocked,
            kSecAttrService:        "user-key-pass",
            kSecAttrAccount:        lookupKey,
            kSecValueData:          password.data(using: .utf8)!
        ]) { (_, new) in new }
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(for: .password, with: status) }
    }

    func retrieveFromiCloud(lookupKey: String) throws -> String? {
        let searchQuery = secretQueryBaseiCloud.merging([
            kSecAttrAccessible:     kSecAttrAccessibleWhenUnlocked,
            kSecAttrService:        "user-key-pass",
            kSecAttrAccount:        lookupKey,
            kSecMatchLimit:         kSecMatchLimitOne,
            kSecReturnAttributes:   false,
            kSecReturnData:         true
        ]) { (_, new) in new }
        var item: CFTypeRef?
        let status = SecItemCopyMatching(searchQuery as CFDictionary, &item)
        guard status != errSecItemNotFound else { return nil }
        guard status == errSecSuccess else { throw KeychainError(for: .password, with: status) }
        guard let data = item as? Data, let password = String(data: data, encoding: .utf8) else { throw KeychainError.unexpectedFormat }
        return password
    }

    func clearFromiCloud(lookupKey: String) {
        let deleteQuery = secretQueryBaseiCloud.merging([
            kSecAttrAccessible:     kSecAttrAccessibleWhenUnlocked,
            kSecAttrService:        "user-key-pass",
            kSecAttrAccount:        lookupKey,
        ]) { (_, new) in new }
        let deleteStatus = SecItemDelete(deleteQuery as CFDictionary)
        guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else { fatalError(KeychainError(for: .key, with: deleteStatus).localizedDescription) }
    }

    func clearAllPasswordsFromiCloud() {
        let deleteQuery = secretQueryBaseiCloud.merging([
            kSecAttrAccessible:     kSecAttrAccessibleWhenUnlocked,
            kSecAttrService:        "user-key-pass",
        ]) { (_, new) in new }
        let deleteStatus = SecItemDelete(deleteQuery as CFDictionary)
        guard deleteStatus == errSecSuccess || deleteStatus == errSecItemNotFound else { fatalError(KeychainError(for: .key, with: deleteStatus).localizedDescription) }
    }
}
