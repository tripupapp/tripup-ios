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
        do {
            var error: NSError?
            guard let encryptedData = HelperEncryptAttachment(binary, nil, publicKeyRing, &error) else {
                throw error ?? "unknown error occurred while encrypting data"
            }
            let encryptedDataOutput = PGPData.with {
                $0.keyPacket = encryptedData.keyPacket!
                $0.dataPacket = encryptedData.dataPacket!
            }
            return try encryptedDataOutput.serializedData()
        } catch {
            fatalError(String(describing: error))
        }
    }

    // 100 KB default chunk size
    func encrypt(fileAtURL url: URL, chunkSize: Int = 100000, outputFilename: String) -> URL? {
        assert(!Thread.isMainThread)
        guard let encryptedOutputFile = FileManager.default.uniqueTempFile(filename: outputFilename) else {
            return nil
        }
        let outputWriter: CryptoWriterProtocol
        do {
            outputWriter = try CryptoFileWriter(encryptedOutputFile)
        } catch {
            assertionFailure(String(describing: error))
            return nil
        }
        guard let goOutputWriter = HelperNewMobile2GoWriter(outputWriter) else {
            assertionFailure()
            return nil
        }

        let inputWriter: CryptoWriteCloserProtocol
        do {
            inputWriter = try publicKeyRing.encryptStream(goOutputWriter, plainMessageMetadata: nil, sign: nil)
        } catch {
            assertionFailure(String(describing: error))
            return nil
        }

        var inputWriterError: Error?
        FileSystem.default.processFile(atURL: url, chunkSize: chunkSize) { (data) in
            do {
                var dataWritten: Int = 0
                try inputWriter.write(data, n: &dataWritten)
            } catch {
                assertionFailure(String(describing: error))
                inputWriterError = error
            }
        }
        guard inputWriterError == nil else {
            try? FileManager.default.removeItem(at: encryptedOutputFile)
            return nil
        }
        do {
            try inputWriter.close()
        } catch {
            assertionFailure(String(describing: error))
            try? FileManager.default.removeItem(at: encryptedOutputFile)
            return nil
        }
        return encryptedOutputFile
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
        } catch let error as NSError where error.domain == "go" && error.localizedDescription == "Signature Verification Error: Missing signature" {
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

    // 100 KB default chunk size
    func decrypt(fileAtURL url: URL, chunkSize: Int = 100000) -> URL? {
        assert(!Thread.isMainThread)
        let inputReader: HelperMobileReaderProtocol
        do {
            inputReader = try CryptoFileReader(url)
        } catch {
            assertionFailure(String(describing: error))
            return nil
        }
        guard let goInputReader = HelperNewMobile2GoReader(inputReader) else {
            assertionFailure()
            return nil
        }

        let privateKeyRing = self.privateKeyRing
        defer {
            privateKeyRing.clearPrivateParams()
        }

        let outputReader: CryptoPlainMessageReader
        do {
            outputReader = try privateKeyRing.decryptStream(goInputReader, verifyKeyRing: nil, verifyTime: CryptoGetUnixTime())
        } catch {
            print(String(describing: error))
            assertionFailure()
            return nil
        }

        guard let goOutputReader = HelperNewGo2IOSReader(outputReader) else {
            assertionFailure()
            return nil
        }

        guard let outputURL = FileManager.default.uniqueTempFile(filename: url.lastPathComponent) else {
            assertionFailure()
            return nil
        }

        var outputWriterError: Error?
        FileSystem.default.write(streamData: { () -> Data? in
            do {
                let result = try goOutputReader.read(chunkSize)
                return result.data
            } catch {
                assertionFailure(String(describing: error))
                outputWriterError = error
                return nil
            }
        }, toURL: outputURL)

        guard outputWriterError == nil else {
            try? FileManager.default.removeItem(at: outputURL)
            return nil
        }

        return outputURL
    }
}

fileprivate class CryptoFileWriter: NSObject {
    let fileHandle: FileHandle

    init(_ url: URL) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil, attributes: nil)
        fileHandle = try FileHandle(forWritingTo: url)
    }
}

extension CryptoFileWriter: CryptoWriterProtocol {
    func write(_ data: Data?, n: UnsafeMutablePointer<Int>?) throws {
        if let data = data {
            try fileHandle.write(contentsOf: data)
            n?.pointee = data.count
        } else {
            n?.pointee = 0
        }
    }
}

fileprivate class CryptoFileReader: NSObject {
    let fileHandle: FileHandle

    init(_ url: URL) throws {
        fileHandle = try FileHandle(forReadingFrom: url)
    }
}

extension CryptoFileReader: HelperMobileReaderProtocol {
    func read(_ max: Int) throws -> HelperMobileReadResult {
        let data = fileHandle.readData(ofLength: max)
        if let result = HelperNewMobileReadResult(data.count, data.count < max, data) {
            return result
        } else {
            throw NSError(domain: "app.tripup.cryptofilereader", code: 1, userInfo: nil)
        }
    }
}
