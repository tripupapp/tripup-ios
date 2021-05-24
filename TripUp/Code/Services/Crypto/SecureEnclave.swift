//
//  SecureEnclave.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 09/02/2020.
//  Copyright © 2020 Vinoth Ramiah. All rights reserved.
//

/*
 SecureEnclave code. Works as of iOS 13 SDK, but unused. Kept for future reference
 */

/**

func generateSecureEnclaveKey() -> SecKey {
    var error: Unmanaged<CFError>? = nil

    guard let access = SecAccessControlCreateWithFlags(kCFAllocatorDefault, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, [.privateKeyUsage, .biometryAny], &error) else {
        fatalError("unable to create access control object. error: \(error!.takeRetainedValue().localizedDescription)")
    }
    let attributes: [CFString: Any] = [
        kSecAttrKeyType:            kSecAttrKeyTypeECSECPrimeRandom,
        kSecAttrKeySizeInBits:      256,
        kSecAttrTokenID:            kSecAttrTokenIDSecureEnclave,
        kSecAttrCreator:            KeychainCreator.USER,
        kSecAttrLabel:              environment.rawValue,
        kSecPrivateKeyAttrs: [
            kSecAttrIsPermanent:        true,
            kSecAttrApplicationTag:     "app.tripup.keys.user.secure".data(using: .utf8)!,
            kSecAttrAccessControl:      access
        ]
    ]
    guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
        fatalError("unable to create private key. error: \(error!.takeRetainedValue().localizedDescription)")
    }
    return privateKey
}

func fingerprint(for key: SecKey) -> String {
    let attributes = SecKeyCopyAttributes(key)! as! [CFString: Any]
    let data = attributes[kSecAttrApplicationLabel] as! Data    // iOS framework generates this as CFData instead of CFString (despite documentation saying otherwise 😡) http://openradar.appspot.com/24496368
    return data.base64EncodedString()   // the data isn't even a proper string though... no idea wth it is so lets just base64 encode to string and base64 decode when searching 🤦‍♂️
}

func deleteAllSecureEnclaveKeys() {
    let query: [CFString: Any] = [
        kSecClass:                  kSecClassKey,
        kSecAttrTokenID:            kSecAttrTokenIDSecureEnclave,
        kSecAttrApplicationTag:     "app.tripup.keys.user.secure".data(using: .utf8)!,
        kSecAttrCreator:            KeychainCreator.USER,
        kSecAttrLabel:              environment.rawValue
    ]

    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else { fatalError(KeychainError(for: .key, with: status).localizedDescription) }
}

func deleteSecureEnclaveKey(_ key: SecKey) {
    let attributes = SecKeyCopyAttributes(key)! as! [CFString: Any]
    let query: [CFString: Any] = [
        kSecClass:                  kSecClassKey,
        kSecAttrTokenID:            kSecAttrTokenIDSecureEnclave,
        kSecAttrApplicationTag:     "app.tripup.keys.user.secure".data(using: .utf8)!,
        kSecAttrApplicationLabel:   attributes[kSecAttrApplicationLabel] as! Data,
        kSecAttrCreator:            KeychainCreator.USER,
        kSecAttrLabel:              environment.rawValue
    ]

    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess else { fatalError(KeychainError(for: .key, with: status).localizedDescription) }
}

func findKey(fingerprint: String) -> SecKey? {
    let fingerprintData = Data(base64Encoded: fingerprint)! // see fingerprint section comments
    let query: [CFString: Any] = [
        kSecClass:                  kSecClassKey,
        kSecAttrTokenID:            kSecAttrTokenIDSecureEnclave,
        kSecAttrApplicationTag:     "app.tripup.keys.user.secure".data(using: .utf8)!,
        kSecAttrApplicationLabel:   fingerprintData,
        kSecAttrCreator:            KeychainCreator.USER,
        kSecAttrLabel:              environment.rawValue,
        kSecMatchLimit:             kSecMatchLimitOne,
        kSecReturnAttributes:       false,
        kSecReturnRef:              true
    ]
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status != errSecItemNotFound else { return nil }
    guard status == errSecSuccess else { fatalError(KeychainError(for: .key, with: status).localizedDescription) }
    return (item! as! SecKey)
}

private func encrypt(_ plainText: String, with publicKey: SecKey, signedWith privateKey: SecKey?) throws -> (cipherText: String, signature: String?) {
    var error: Unmanaged<CFError>?

    let encryptionAlgo: SecKeyAlgorithm = .eciesEncryptionCofactorX963SHA256AESGCM
    guard SecKeyIsAlgorithmSupported(publicKey, .encrypt, encryptionAlgo) else {
        preconditionFailure("encryption algorithm not suitable for key")
    }
    guard let cipher = SecKeyCreateEncryptedData(publicKey, encryptionAlgo, plainText.data(using: .utf8)! as CFData, &error) as Data? else {
        fatalError("unable to encrypt text. error: \(error!.takeRetainedValue().localizedDescription)")
    }

    if let privateKey = privateKey {
        let signatureAlgo: SecKeyAlgorithm = .ecdsaSignatureMessageX962SHA512
        guard SecKeyIsAlgorithmSupported(privateKey, .sign, signatureAlgo) else {
            preconditionFailure("signature algorithm not suitable for key")
        }
        guard let signature = SecKeyCreateSignature(privateKey, signatureAlgo, cipher as CFData, &error) as Data? else {
            let error = error!.takeRetainedValue() as Error as NSError
            if error.domain == kLAErrorDomain {
                log.error(error)
                throw LAError(_nsError: error)
            }
            fatalError("unable to sign data. error: \(error)")
        }

        return (cipherText: cipher.base64EncodedString(), signature: signature.base64EncodedString())
    } else {
        return (cipherText: cipher.base64EncodedString(), nil)
    }
}

private func decrypt(_ cipherText: String, with privateKey: SecKey, verify signatureData: (signature: String, publicKey: SecKey)?) -> String? {
    let cipher = Data(base64Encoded: cipherText)!
    var error: Unmanaged<CFError>?

    let decryptionAlgo: SecKeyAlgorithm = .eciesEncryptionCofactorX963SHA256AESGCM
    guard SecKeyIsAlgorithmSupported(privateKey, .decrypt, decryptionAlgo) else {
        preconditionFailure("decryption algorithm not suitable for key")
    }
    guard let decryptedData = SecKeyCreateDecryptedData(privateKey, decryptionAlgo, cipher as CFData, &error) as Data? else {
        log.warning("unable to decrypt data with the key supplied. error: \(error!.takeRetainedValue().localizedDescription)")
        return nil
    }

    if let signatureData = signatureData {
        let verificationAlgo: SecKeyAlgorithm = .ecdsaSignatureMessageX962SHA512
        guard SecKeyIsAlgorithmSupported(signatureData.publicKey, .verify, verificationAlgo) else {
            preconditionFailure("verification algorithm not suitable for key")
        }
        guard SecKeyVerifySignature(signatureData.publicKey, verificationAlgo, cipher as CFData, Data(base64Encoded: signatureData.signature)! as CFData, &error) else {
            log.error("unable to verify signature data")
            return nil
        }
    }
    return String(data: decryptedData, encoding: .utf8)!
}

 */
