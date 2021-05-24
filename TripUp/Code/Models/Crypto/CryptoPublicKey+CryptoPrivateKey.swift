//
//  CryptoPublicKey+CryptoPrivateKey.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 10/06/2019.
//  Copyright © 2019 Vinoth Ramiah. All rights reserved.
//

import Foundation
import Gopenpgp

// MARK: Public Key Object
class CryptoPublicKey {
    var data: Data {
        var error: NSError?
        let keyString = key.armor(&error)
        if let error = error {
            fatalError(String(describing: error))
        }
        return keyString.data(using: .utf8)!
    }
    
    var fingerprint: String {
        return key.getFingerprint()
    }

    fileprivate var publicKeyRing: CryptoKeyRing {
        return CryptoKeyRing(key)!
    }

    let type: KeyType
    fileprivate let key: CryptoKey

    fileprivate init(key: CryptoKey, type: KeyType) {
        self.key = key
        self.type = type
    }

    required convenience init(key: String, for type: KeyType) throws {
        guard let key = CryptoKey(fromArmored: key) else { throw KeyConstructionError.invalidKeyString }
        guard !key.isPrivate() else { throw KeyConstructionError.privateKeyUsedAsPublicKey }
        self.init(key: key, type: type)
    }
}

extension CryptoPublicKey: Hashable {
    static func == (lhs: CryptoPublicKey, rhs: CryptoPublicKey) -> Bool {
        return lhs.fingerprint == rhs.fingerprint
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(key)
        hasher.combine(type)
    }
}

extension CryptoPublicKey: AsymmetricPublicKey {
    var `public`: String {
        var error: NSError?
        let publicKey = key.getArmoredPublicKey(&error)
        if let error = error {
            fatalError(String(describing: error))
        }
        return publicKey
    }

    func encrypt(_ string: String, signed privateKey: CryptoPrivateKey?) -> String {
        let privateKeyRing = privateKey?.privateKeyRing
        defer {
            privateKeyRing?.clearPrivateParams()
        }
        guard let pgpMessage = try? publicKeyRing.encrypt(CryptoNewPlainMessageFromString(string), privateKey: privateKeyRing) else { fatalError() }
        var error: NSError?
        let cipher = pgpMessage.getArmored(&error)
        if let error = error {
            fatalError(String(describing: error))
        }
        return cipher
    }

    func encrypt(_ binary: Data) -> Data {
        var error: NSError?
        guard let encryptedData = HelperEncryptAttachment(binary, nil, publicKeyRing, &error) else { fatalError(String(describing: error)) }
        let encryptedDataOutput = PGPData.with {
            $0.keyPacket = encryptedData.keyPacket!
            $0.dataPacket = encryptedData.dataPacket!
        }
        return try! encryptedDataOutput.serializedData()
    }
}

// MARK: Private Key Object
class CryptoPrivateKey: CryptoPublicKey {
    override fileprivate var publicKeyRing: CryptoKeyRing {
        let publicKey = try! key.toPublic()
        return CryptoKeyRing(publicKey)!
    }

    fileprivate var privateKeyRing: CryptoKeyRing {
        let unlockedKey = try! key.unlock(password?.data(using: .utf8)!)
        return CryptoKeyRing(unlockedKey)!
    }

    let password: String?

    required init(key: String, password: String?, for type: KeyType) throws {
        guard let key = CryptoKey(fromArmored: key) else { throw KeyConstructionError.invalidKeyString }
        guard key.isPrivate() else { throw KeyConstructionError.publicKeyUsedAsPrivateKey }
        // validate password to unlock is correct
        do {
            let unlockedKey = try key.unlock(password?.data(using: .utf8))
            unlockedKey.clearPrivateParams()
        } catch let error as NSError where error.domain == "go" && error.localizedDescription == "gopenpgp: error in unlocking key: openpgp: invalid data: private key checksum failure" {
            throw password == nil ? KeyConstructionError.passwordRequiredForKey : KeyConstructionError.invalidPasswordForKey
        }

        self.password = password
        super.init(key: key, type: type)
    }

    required convenience init(_ type: KeyType, password: String?) {
        var error: NSError?
        let key = HelperGenerateKey(UUID().string, String(describing: type) + ".keys@tripup.app", password?.data(using: .utf8), "x25519", 256, &error)
        if let error = error {
            fatalError(String(describing: error))
        }
        try! self.init(key: key, password: password, for: type)
    }

    required convenience init(key: String, for type: KeyType) throws {
        fatalError("This is a public key initializer")
    }

    deinit {
        key.clearPrivateParams()
    }
}

extension CryptoPrivateKey: AsymmetricPrivateKey {
    var `private`: String {
        var error: NSError?
        let privateKeyString = key.armor(&error)
        if let error = error {
            fatalError(String(describing: error))
        }
        return privateKeyString
    }

    func decrypt(_ cipher: String, signedByOneOf potentialSignatories: [CryptoPublicKey]) throws -> (String, CryptoPublicKey) {
        var result: String?
        var signature: CryptoPublicKey?
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

    func decrypt(_ cipher: String, signedBy publicKey: CryptoPublicKey?) throws -> String {
        let privateKeyRing = self.privateKeyRing
        defer {
            privateKeyRing.clearPrivateParams()
        }
        do {
            let message = try privateKeyRing.decrypt(CryptoPGPMessage(fromArmored: cipher), verifyKey: publicKey?.publicKeyRing, verifyTime: CryptoGetUnixTime())
            return message.getString()
        } catch let error as NSError where error.domain == "go" && error.localizedDescription == "gopenpgp: error in reading message: openpgp: incorrect key" {
            throw KeyMessageError.incorrectKeyUsedToDecrypt
        } catch let error as NSError where error.domain == "go" && error.localizedDescription == "Signature Verification Error: No matching signature" {
            throw KeyMessageError.invalidSignature
        }
    }

    func decrypt(_ binary: Data) throws -> Data {
        guard binary.isNotEmpty else { throw KeyMessageError.noData }
        guard let encrypted = try? PGPData(serializedData: binary) else { throw KeyMessageError.invalidPGPData }

        let privateKeyRing = self.privateKeyRing
        defer {
            privateKeyRing.clearPrivateParams()
        }

        var error: NSError?
        let message = HelperDecryptAttachment(encrypted.keyPacket, encrypted.dataPacket, privateKeyRing, &error)
        if let error = error {
            if error.domain == "go", error.localizedDescription == "gopenpgp: unable to decrypt attachment: gopengpp: unable to read attachment: openpgp: incorrect key" {
                throw KeyMessageError.incorrectKeyUsedToDecrypt
            } else {
                fatalError(String(describing: error))
            }
        }
        return message!.getBinary()!
    }
}
