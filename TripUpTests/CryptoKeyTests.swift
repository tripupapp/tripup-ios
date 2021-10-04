//
//  CryptoKeyTests.swift
//  TripUpTests
//
//  Created by Vinoth Ramiah on 13/06/2019.
//  Copyright © 2019 Vinoth Ramiah. All rights reserved.
//

import XCTest
@testable import TripUp

class CryptoKeyTests: XCTestCase {
    private let testKeyString1 = """
    -----BEGIN PGP PRIVATE KEY BLOCK-----
    Version: GopenPGP 0.0.1 (ddacebe0)
    Comment: https://gopenpgp.org

    xYYEXP/S9BYJKwYBBAHaRw8BAQhA/0+3BNETkz1fRQPmE8tdIUlI3F+Ue9bhJmqf
    u/Yh0yz+CQMIcNmAeeWkvbRgvLjF3ZFWwr3VgpKDcqZCVIxSjztv+xQsGwPoNb3q
    RJxElcKZu8GpqfiVIayvpQgK/JI2+xsfn6Y3+cEZIPvuM1lRzo7VE81hNWZlZmY3
    OGYtZThmNS00ODc2LTkzOTQtMmNmYjViY2VjYzhmQHRyaXB1cC5hcHAgPDVmZWZm
    NzhmLWU4ZjUtNDg3Ni05Mzk0LTJjZmI1YmNlY2M4ZkB0cmlwdXAuYXBwPsJqBBMW
    CAAcBQJc/9L0CRDpAimdIkG/FgIbAwIZAQILCQIVCAAASUABABvrjbR2VuOtNi0j
    kOiTV/TU6tpJS+EuaSCc/sVO2gpyAQDNFF7/zdnvW9z7QKu6PCK8tiB+EC+aCUm2
    oyHhCE9KDseLBFz/0vQSCisGAQQBl1UBBQEBCEBF6BQ7uXpYBPGo4k00x+7khG60
    OMw7+TjweJp0aJh2BQMBCgn+CQMIfqLvVhm0SNNgk7mkKmVkqoj0GhtcGFDO2zE5
    9exgJmZ7z6OtXk4RxhaPETW9Kj74M0ZE8PIGqwXavjduLfIjmjfiWGvJi2STNh+a
    gJWBUsJhBBgWCAATBQJc/9L0CRDpAimdIkG/FgIbDAAAQJoBANMXz/lWTYQo8ghE
    PeWmXODSkcO4aI+t4c92WR3BbC+bAQAXNJzubGKuLXwVMHg9pWfYqH2fMm/tkdeJ
    LeFQ7MzjDQ==
    =ZmzT
    -----END PGP PRIVATE KEY BLOCK-----
    """ // x25519 private key, 256 bits, password protected, username: 5feff78f-e8f5-4876-9394-2cfb5bcecc8f, domain: tripup.app
    private let testKeyPassword1 = "dokZzkR00ugguYjwVbm++um+6b1c/204veF9zYO0TN0="

    private let testKeyPublicString1 = """
    -----BEGIN PGP PUBLIC KEY BLOCK-----

    xjMEXP/S9BYJKwYBBAHaRw8BAQhA/0+3BNETkz1fRQPmE8tdIUlI3F+Ue9bhJmqf
    u/Yh0yzNYTVmZWZmNzhmLWU4ZjUtNDg3Ni05Mzk0LTJjZmI1YmNlY2M4ZkB0cmlw
    dXAuYXBwIDw1ZmVmZjc4Zi1lOGY1LTQ4NzYtOTM5NC0yY2ZiNWJjZWNjOGZAdHJp
    cHVwLmFwcD7CagQTFggAHAUCXP/S9AkQ6QIpnSJBvxYCGwMCGQECCwkCFQgAAElA
    AQAb6420dlbjrTYtI5Dok1f01OraSUvhLmkgnP7FTtoKcgEAzRRe/83Z71vc+0Cr
    ujwivLYgfhAvmglJtqMh4QhPSg7OOARc/9L0EgorBgEEAZdVAQUBAQhARegUO7l6
    WATxqOJNNMfu5IRutDjMO/k48HiadGiYdgUDAQoJwmEEGBYIABMFAlz/0vQJEOkC
    KZ0iQb8WAhsMAABAmgEA0xfP+VZNhCjyCEQ95aZc4NKRw7hoj63hz3ZZHcFsL5sB
    ABc0nO5sYq4tfBUweD2lZ9iofZ8yb+2R14kt4VDszOMN
    =MlDh
    -----END PGP PUBLIC KEY BLOCK-----
    """

    private let testKeyString2 = """
    -----BEGIN PGP PRIVATE KEY BLOCK-----
    Version: GopenPGP 0.0.1 (ddacebe0)
    Comment: https://gopenpgp.org

    xYYEXP/qpBYJKwYBBAHaRw8BAQhATRFTZfH/LM51azkKCYNAngI1wm6S6AvPSz42
    O+3ctCr+CQMIDmqnInLFEWtgVmlwmhobtX6hIeJVmfOD3+odPkUKW9clT2/uHErC
    MnUAX6KQbS0JHktY4fwhiiKqqBqUGZi0gTuHIlC0MMyWUn6oSt8LnM1hNWZlZmY3
    OGYtZThmNS00ODc2LTkzOTQtMmNmYjViY2VjYzhmQHRyaXB1cC5hcHAgPDVmZWZm
    NzhmLWU4ZjUtNDg3Ni05Mzk0LTJjZmI1YmNlY2M4ZkB0cmlwdXAuYXBwPsJqBBMW
    CAAcBQJc/+qkCRBMt+5fBk32dQIbAwIZAQILCQIVCAAAl0sBAF3rRAfWzlNDgsVD
    Wd5mzURbpOm+j131ObQngqIvWShZAQC//wu7I6A4E4ekbhINnAdLHW7o9Bo++FET
    e82osW4oCceLBFz/6qQSCisGAQQBl1UBBQEBCEApWdhTMB70RbCzzdQJEjJtu1IK
    MoDNiMvoM3VDsghnOQMBCgn+CQMIixfB/TV8g3ZggEfz5rHckLO5LlkoFOYBE5VS
    XPfdaKg+GLNtvi3Y2eqGhxEQZOjcZMAi3V+9Gd0dA9AANiP1Wf2vVa9KQjKOxqri
    cqZUAMJhBBgWCAATBQJc/+qkCRBMt+5fBk32dQIbDAAAtxgBAF8Gi56nGpWt6E+e
    H50DUrTErFZpG9gfLzs5pgHUZfC7AQClBDTBwma9ePUXHWTiDH1xDk75cXgkve21
    +wh9WGzVBA==
    =8/Zq
    -----END PGP PRIVATE KEY BLOCK-----
    """ // x25519 private key, 256 bits, NOT password protected, username: 5feff78f-e8f5-4876-9394-2cfb5bcecc8f, domain: tripup.app

    func testKeyRecreation() {
        // valid key format
        XCTAssertNoThrow(try CryptoPrivateKey(key: testKeyString1, password: testKeyPassword1, for: .user))
        XCTAssertNoThrow(try CryptoPrivateKey(key: testKeyString2, password: nil, for: .asset))
        XCTAssertNoThrow(try CryptoPublicKey(key: testKeyPublicString1, for: .user))

        // invalid key format
        XCTAssertThrowsError(try CryptoPrivateKey(key: "bad_key", password: nil, for: .generic)) { errorThrown in
            guard let error = errorThrown as? KeyConstructionError else { print(errorThrown); XCTFail(); return }
            XCTAssertEqual(error, KeyConstructionError.invalidKeyString)
        }
        XCTAssertThrowsError(try CryptoPrivateKey(key: "bad_key", password: testKeyPassword1, for: .generic)) { errorThrown in
            guard let error = errorThrown as? KeyConstructionError else { print(errorThrown); XCTFail(); return }
            XCTAssertEqual(error, KeyConstructionError.invalidKeyString)
        }
        XCTAssertThrowsError(try CryptoPublicKey(key: "bad_key", for: .generic)) { errorThrown in
            guard let error = errorThrown as? KeyConstructionError else { print(errorThrown); XCTFail(); return }
            XCTAssertEqual(error, KeyConstructionError.invalidKeyString)
        }

        // invalid password
        XCTAssertThrowsError(try CryptoPrivateKey(key: testKeyString1, password: "OTY0ZDY2MjQtYmY4OC00NGZmLTliYWQtOGZhOTgzZGQxNTFm", for: .user)) { errorThrown in
            guard let error = errorThrown as? KeyConstructionError else { print(errorThrown); XCTFail(); return }
            XCTAssertEqual(error, KeyConstructionError.invalidPasswordForKey)
        }

        // no password despite password protected key
        XCTAssertThrowsError(try CryptoPrivateKey(key: testKeyString1, password: nil, for: .user)) { errorThrown in
            guard let error = errorThrown as? KeyConstructionError else { print(errorThrown); XCTFail(); return }
            XCTAssertEqual(error, KeyConstructionError.passwordRequiredForKey)
        }

        // password despite non-password protected key
        XCTAssertThrowsError(try CryptoPrivateKey(key: testKeyString2, password: testKeyPassword1, for: .asset)) { errorThrown in
            guard let error = errorThrown as? KeyConstructionError else { print(errorThrown); XCTFail(); return }
            XCTAssertEqual(error, KeyConstructionError.invalidPasswordForKey)
        }

        // attempt to use a public key string in a private key pair object
        XCTAssertThrowsError(try CryptoPrivateKey(key: testKeyPublicString1, password: nil, for: .user)) { errorThrown in
            guard let error = errorThrown as? KeyConstructionError else { print(errorThrown); XCTFail(); return }
            XCTAssertEqual(error, KeyConstructionError.publicKeyUsedAsPrivateKey)
        }
        XCTAssertThrowsError(try CryptoPrivateKey(key: testKeyPublicString1, password: testKeyPassword1, for: .user)) { errorThrown in
            guard let error = errorThrown as? KeyConstructionError else { print(errorThrown); XCTFail(); return }
            XCTAssertEqual(error, KeyConstructionError.publicKeyUsedAsPrivateKey)
        }

        // attempt to use a private key string in a public key object
        XCTAssertThrowsError(try CryptoPublicKey(key: testKeyString1, for: .user)) { errorThrown in
            guard let error = errorThrown as? KeyConstructionError else { print(errorThrown); XCTFail(); return }
            XCTAssertEqual(error, KeyConstructionError.privateKeyUsedAsPublicKey)
        }
    }

    func testPublicKeyDerivation() {
        let testKey1 = try! CryptoPrivateKey(key: testKeyString1, password: testKeyPassword1, for: .user)
        XCTAssertEqual(testKey1, try? CryptoPublicKey(key: testKeyPublicString1, for: .user))
    }

    func testEncryptMessage() {
        let testKey1 = try! CryptoPrivateKey(key: testKeyString1, password: testKeyPassword1, for: .user)
        let testKey2 = try! CryptoPrivateKey(key: testKeyString2, password: nil, for: .asset)
        let message = "hello world"
        var plainText: String!

        // encrypt and sign with pass protected key, to non-pass protected key
        let cipher = testKey2.encrypt(message, signed: testKey1)
        XCTAssertNoThrow(plainText = try testKey2.decrypt(cipher, signedBy: testKey1))
        XCTAssertEqual(plainText, message)

        // encrypt to non-pass protected key
        let cipher2 = testKey2.encrypt(message, signed: nil)
        XCTAssertNoThrow(plainText = try testKey2.decrypt(cipher2, signedBy: nil))
        XCTAssertEqual(plainText, message)

        // encrypt and sign with non-pass protected key, to pass protected key
        let cipher3 = testKey1.encrypt(message, signed: testKey2)
        XCTAssertNoThrow(plainText = try testKey1.decrypt(cipher3, signedBy: testKey2))
        XCTAssertEqual(plainText, message)

        // encrypt to pass protected key
        let cipher4 = testKey1.encrypt(message, signed: nil)
        XCTAssertNoThrow(plainText = try testKey1.decrypt(cipher4, signedBy: nil))
        XCTAssertEqual(plainText, message)
    }

    func testEncryptData() {
        let testKey = try! CryptoPrivateKey(key: testKeyString1, password: testKeyPassword1, for: .user)
        let message = "hello world"
        XCTAssertNoThrow(testKey.encrypt(message.data(using: .utf8)!))
    }

    func testDecryptSignedMessage() {
        let cipher = """
        -----BEGIN PGP MESSAGE-----

        wV4Dexe00GLDjssSAQhAvMJHUu5F9TCGCHIpkSqVuUO9ym3RrZ4TiUKpkDzXH0Mw
        5ULutK6/swr6q5Qb790KL+mLBEeN9JO9kuw7ByGLi9Y/+Et/VthM9s6dTRreYdad
        0qsB4C4yWHiO4zWJ9pYH4tn1KjMIidk23utmv6B4Cl9fYwu6U63+cgaqelRhf5dW
        MgUDfpxM8/CjueHuBnVXOzEucX4cihdMleuo3F6XnrlcmiqlSD7jd7a2HbkbNTZi
        UU6MjzKQ+oLASMideGkmJNZXIIE3zC8bkTf25U0XngeA0JsP+ksd9l6YepQDp/8U
        q6u3u4xehYMjOPgQr4KDHOAQLXbQf6lwiESELaA=
        =fZ66
        -----END PGP MESSAGE-----
        """ // "hello world", encrypted and signed for user1 key, by same user

        // decrypt and verify
        let testKey = try! CryptoPrivateKey(key: testKeyString1, password: testKeyPassword1, for: .user)
        var plainText: String!
        XCTAssertNoThrow(plainText = try testKey.decrypt(cipher, signedBy: testKey))
        XCTAssertEqual(plainText, "hello world")

        // ignore signature
        XCTAssertNoThrow(try testKey.decrypt(cipher, signedBy: nil))

        // wrong key used to decrypt
        let testKey2 = try! CryptoPrivateKey(key: testKeyString2, password: nil, for: .asset)
        XCTAssertThrowsError(try testKey2.decrypt(cipher, signedBy: nil)) { errorThrown in
            guard let error = errorThrown as? KeyMessageError else { print(errorThrown); XCTFail(); return }
            XCTAssertEqual(error, KeyMessageError.incorrectKeyUsedToDecrypt)
        }
        XCTAssertThrowsError(try testKey2.decrypt(cipher, signedBy: testKey)) { errorThrown in
            guard let error = errorThrown as? KeyMessageError else { print(errorThrown); XCTFail(); return }
            XCTAssertEqual(error, KeyMessageError.incorrectKeyUsedToDecrypt)
        }
        XCTAssertThrowsError(try testKey2.decrypt(cipher, signedBy: testKey2)) { errorThrown in
            guard let error = errorThrown as? KeyMessageError else { print(errorThrown); XCTFail(); return }
            XCTAssertEqual(error, KeyMessageError.incorrectKeyUsedToDecrypt)
        }

        // wrong signature
        XCTAssertThrowsError(try testKey.decrypt(cipher, signedBy: testKey2)) { errorThrown in
            guard let error = errorThrown as? KeyMessageError else { print(errorThrown); XCTFail(); return }
            XCTAssertEqual(error, KeyMessageError.invalidSignature)
        }

        // decrypt and verify one of the supplied signatures is correct
        var signingKey: CryptoPublicKey!
        XCTAssertNoThrow((plainText, signingKey) = try testKey.decrypt(cipher, signedByOneOf: [testKey, testKey2]))
        XCTAssertEqual(plainText, "hello world")
        XCTAssertEqual(signingKey, testKey)
    }

    func testDecryptUnsignedMessage() {
        let cipher = """
        -----BEGIN PGP MESSAGE-----

        wV4Dexe00GLDjssSAQhAq4ic/K0O/eGIQ9GXM8XRCopKt2WZQ5E2PuOmMkE+n1sw
        9J8pKLQuSPAERo2g84Cvcyjd7lJ7ZC+hWsoiKL0T1JKQ708bnmBQWFbKrINjvcRp
        0jwBzzcTjUBn4z+A/4V/EDGdsBq1TkTYFv3mSabnW2jkjmWIi4fu6p0COrDl7qcg
        0A6aYW3VSi0FrZXehoc=
        =QDUD
        -----END PGP MESSAGE-----
        """ // "hello world", encrypted for user1, by same user

        // decrypt
        let testKey = try! CryptoPrivateKey(key: testKeyString1, password: testKeyPassword1, for: .user)
        var plainText: String!
        XCTAssertNoThrow(plainText = try testKey.decrypt(cipher, signedBy: nil))
        XCTAssertEqual(plainText, "hello world")

        // wrong key used to decrypt
        let testKey2 = try! CryptoPrivateKey(key: testKeyString2, password: nil, for: .asset)
        XCTAssertThrowsError(try testKey2.decrypt(cipher, signedBy: nil)) { errorThrown in
            guard let error = errorThrown as? KeyMessageError else { print(errorThrown); XCTFail(); return }
            XCTAssertEqual(error, KeyMessageError.incorrectKeyUsedToDecrypt)
        }
        XCTAssertThrowsError(try testKey2.decrypt(cipher, signedBy: testKey)) { errorThrown in
            guard let error = errorThrown as? KeyMessageError else { print(errorThrown); XCTFail(); return }
            XCTAssertEqual(error, KeyMessageError.incorrectKeyUsedToDecrypt)
        }
        XCTAssertThrowsError(try testKey2.decrypt(cipher, signedBy: testKey2)) { errorThrown in
            guard let error = errorThrown as? KeyMessageError else { print(errorThrown); XCTFail(); return }
            XCTAssertEqual(error, KeyMessageError.incorrectKeyUsedToDecrypt)
        }

        // expected signature
        XCTAssertThrowsError(try testKey.decrypt(cipher, signedBy: testKey)) { errorThrown in
            guard let error = errorThrown as? KeyMessageError else { print(errorThrown); XCTFail(); return }
            XCTAssertEqual(error, KeyMessageError.invalidSignature)
        }
        XCTAssertThrowsError(try testKey.decrypt(cipher, signedBy: testKey2)) { errorThrown in
            guard let error = errorThrown as? KeyMessageError else { print(errorThrown); XCTFail(); return }
            XCTAssertEqual(error, KeyMessageError.invalidSignature)
        }
    }

    func testDecryptSignedMessageForUser2() {
        let cipher = """
        -----BEGIN PGP MESSAGE-----

        wV4DKaNbZjzUg5YSAQhA3RfFZOfzV45vhtbuw0sBbtFjPTpob8tWyVrSXsidzQAw
        ThqGXg75RXHmiVQF0ZsB6xiqShypW6bJIvTXmc7nhB6wxUKfeMU4qQ4k9+uSxiBD
        0qsB55BXc5zbMX6WQ1i+XQzMFedThdl6h/xo8Qve/5zknnnhVBcb2sgymiOgmX9G
        vtP6vU5JhcbbwQQfPwFoVJM9BtflpIQoCmU7LOXthLCXUzkpf+nkxaQTTiiKeyg8
        IWQVBmvAhDGQwvJZ08aKjX6HZ7qarCA3Ko2ps7l/KeSQyScasit+R9W9kTdHRY+U
        3yiNwDwJD8jMA71vhQHRiBiQPQyqsnfsBmmu//A=
        =t2vX
        -----END PGP MESSAGE-----
        """ // "hello world", encrypted and signed for user2, by user1

        let testKey1 = try! CryptoPrivateKey(key: testKeyString1, password: testKeyPassword1, for: .user)
        let testKey2 = try! CryptoPrivateKey(key: testKeyString2, password: nil, for: .asset)

        // decrypt and verify
        var plainText: String!
        XCTAssertNoThrow(plainText = try testKey2.decrypt(cipher, signedBy: testKey1))
        XCTAssertEqual(plainText, "hello world")

        // ignore signature
        XCTAssertNoThrow(try testKey2.decrypt(cipher, signedBy: nil))

        // wrong key used to decrypt
        XCTAssertThrowsError(try testKey1.decrypt(cipher, signedBy: nil)) { errorThrown in
            guard let error = errorThrown as? KeyMessageError else { print(errorThrown); XCTFail(); return }
            XCTAssertEqual(error, KeyMessageError.incorrectKeyUsedToDecrypt)
        }
        XCTAssertThrowsError(try testKey1.decrypt(cipher, signedBy: testKey1)) { errorThrown in
            guard let error = errorThrown as? KeyMessageError else { print(errorThrown); XCTFail(); return }
            XCTAssertEqual(error, KeyMessageError.incorrectKeyUsedToDecrypt)
        }
        XCTAssertThrowsError(try testKey1.decrypt(cipher, signedBy: testKey2)) { errorThrown in
            guard let error = errorThrown as? KeyMessageError else { print(errorThrown); XCTFail(); return }
            XCTAssertEqual(error, KeyMessageError.incorrectKeyUsedToDecrypt)
        }

        // wrong signature
        XCTAssertThrowsError(try testKey2.decrypt(cipher, signedBy: testKey2)) { errorThrown in
            guard let error = errorThrown as? KeyMessageError else { print(errorThrown); XCTFail(); return }
            XCTAssertEqual(error, KeyMessageError.invalidSignature)
        }
    }

    func testDecryptUnsignedMessageForUser2() {
        let cipher = """
        -----BEGIN PGP MESSAGE-----

        wV4DKaNbZjzUg5YSAQhA5pU3uipIOPE6Cv9Fjyu9Dqx4AszXlEQ3sU7TzDWpFnAw
        t3N08HUNLkbkOS39TJOoDhiJHGSqJYfvjgEvVGkqEPzQjmx1is2nmWL/mmC5/LZw
        0jwBtLphIruHZLE5SzHcSre8gzlACN/2+J7tQMd8frxl55PdGOMbOQtTv7WPIWGZ
        XKlW+6ItGaHERNpmbok=
        =qYpd
        -----END PGP MESSAGE-----
        """ // "hello world", encrypted for user2, by user1

        let testKey1 = try! CryptoPrivateKey(key: testKeyString1, password: testKeyPassword1, for: .user)
        let testKey2 = try! CryptoPrivateKey(key: testKeyString2, password: nil, for: .asset)

        // decrypt
        var plainText: String!
        XCTAssertNoThrow(plainText = try testKey2.decrypt(cipher, signedBy: nil))
        XCTAssertEqual(plainText, "hello world")

        // wrong key used to decrypt
        XCTAssertThrowsError(try testKey1.decrypt(cipher, signedBy: nil)) { errorThrown in
            guard let error = errorThrown as? KeyMessageError else { print(errorThrown); XCTFail(); return }
            XCTAssertEqual(error, KeyMessageError.incorrectKeyUsedToDecrypt)
        }
        XCTAssertThrowsError(try testKey1.decrypt(cipher, signedBy: testKey1)) { errorThrown in
            guard let error = errorThrown as? KeyMessageError else { print(errorThrown); XCTFail(); return }
            XCTAssertEqual(error, KeyMessageError.incorrectKeyUsedToDecrypt)
        }
        XCTAssertThrowsError(try testKey1.decrypt(cipher, signedBy: testKey2)) { errorThrown in
            guard let error = errorThrown as? KeyMessageError else { print(errorThrown); XCTFail(); return }
            XCTAssertEqual(error, KeyMessageError.incorrectKeyUsedToDecrypt)
        }

        // expected signature
        XCTAssertThrowsError(try testKey2.decrypt(cipher, signedBy: testKey1)) { errorThrown in
            guard let error = errorThrown as? KeyMessageError else { print(errorThrown); XCTFail(); return }
            XCTAssertEqual(error, KeyMessageError.invalidSignature)
        }
        XCTAssertThrowsError(try testKey2.decrypt(cipher, signedBy: testKey2)) { errorThrown in
            guard let error = errorThrown as? KeyMessageError else { print(errorThrown); XCTFail(); return }
            XCTAssertEqual(error, KeyMessageError.invalidSignature)
        }
    }

    func testDecryptData() {
        let testKey = try! CryptoPrivateKey(key: testKeyString1, password: testKeyPassword1, for: .user)
        let message = "hello world"
        let encrypted = testKey.encrypt(message.data(using: .utf8)!)
        var decrypted: Data!
        XCTAssertNoThrow(decrypted = try testKey.decrypt(encrypted))
        XCTAssertEqual(String(data: decrypted, encoding: .utf8)!, message)
    }

    func testDecryptDataWrongKey() {
        let testKey1 = try! CryptoPrivateKey(key: testKeyString1, password: testKeyPassword1, for: .user)
        let testKey2 = try! CryptoPrivateKey(key: testKeyString2, password: nil, for: .asset)
        let message = "hello world"
        let encrypted = testKey1.encrypt(message.data(using: .utf8)!)
        XCTAssertThrowsError(try testKey2.decrypt(encrypted)) { errorThrown in
            guard let error = errorThrown as? KeyMessageError else { print(errorThrown); XCTFail(); return }
            XCTAssertEqual(error, KeyMessageError.incorrectKeyUsedToDecrypt)
        }
    }

    func testDecryptDataInvalid() {
        let testKey = try! CryptoPrivateKey(key: testKeyString1, password: testKeyPassword1, for: .user)
        XCTAssertThrowsError(try testKey.decrypt(Data())) { errorThrown in
            guard let error = errorThrown as? KeyMessageError else { print(errorThrown); XCTFail(); return }
            XCTAssertEqual(error, KeyMessageError.noData)
        }
        XCTAssertThrowsError(try testKey.decrypt("Data()".data(using: .utf8)!)) { errorThrown in
            guard let error = errorThrown as? KeyMessageError else { print(errorThrown); XCTFail(); return }
            XCTAssertEqual(error, KeyMessageError.invalidLegacyPGPData)
        }
    }
}
