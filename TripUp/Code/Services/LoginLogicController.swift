//
//  LoginLogicController.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 18/01/2020.
//  Copyright © 2020 Vinoth Ramiah. All rights reserved.
//

import AuthenticationServices
import Foundation

import CryptoSwift
import FirebaseAuth

protocol LoginAPI {
    func getUUID(callbackOn queue: DispatchQueue, resultHandler: @escaping (_ success: Bool, _ userData: (uuid: UUID, privateKey: String, schemaVersion: String)?) -> Void)
    func createUser(publicKey: String, privateKey: String, callbackOn queue: DispatchQueue, resultHandler: @escaping (_ success: Bool, _ uuid: UUID?) -> Void)
    func updateContactDetails()
}

enum LoginError: Error {
    case phoneNumberError
    case verificationCodeError
    case emailError
    case emailVerificationError
    case appleError
    case apiError
}

enum LoginState {
    case pendingNumberVerification(String, String)
    case pendingEmailVerification(String)
    case authenticated(APIUser)
    case loggedIn
    case passwordRequired((String) -> Bool)
    case failed(LoginError)
}

struct LoginPhoneNumber: Codable {
    let phoneNumber: String
    let verificationID: String
}

struct UserKeyPassword {
    let cipher: String
    let signature: String
}

struct SecureKeyExport {
    let fingerprint: String
    let name: String
}

class LoginLogicController {
    typealias Callback = (LoginState) -> Void

    let phoneVerificationCodeLength = 6

    private let log = Logger.self
    private let emailAuthFallbackURL: URL

    @available(iOS 13.0, *)
    private lazy var appleAuthContext = AppleAuthContext()

    init(emailAuthFallbackURL: URL) {
        self.emailAuthFallbackURL = emailAuthFallbackURL
    }

    func isSignIn(link: URL) -> Bool {
        return Auth.auth().isSignIn(withEmailLink: link.absoluteString)
    }

    func login(number: String, callback: @escaping Callback) {
        PhoneAuthProvider.provider().verifyPhoneNumber(number, uiDelegate: nil) { (verificationID, error) in
            if let error = error {
                self.log.error(error.localizedDescription)
                callback(.failed(.phoneNumberError))
            } else {
                callback(.pendingNumberVerification(number, verificationID!))
            }
        }
    }

    func login(email: String, callback: @escaping Callback) {
        let actionCodeSettings = ActionCodeSettings()
        actionCodeSettings.url = emailAuthFallbackURL
        actionCodeSettings.handleCodeInApp = true   // must be true for email link authentication (sdk crash specifically for this otherwise)
        actionCodeSettings.setIOSBundleID(Bundle.main.bundleIdentifier!)
        Auth.auth().sendSignInLink(toEmail: email, actionCodeSettings: actionCodeSettings) { error in
            if let error = error {
                self.log.error(error)
                callback(.failed(.emailError))
                return
            }
            callback(.pendingEmailVerification(email))
        }
    }

    @available(iOS 13, *)
    func loginWithApple(presentingController: ASAuthorizationControllerPresentationContextProviding, callback: @escaping Callback) {
        signInWithApple(presentingController: presentingController) { [log] credential in
            if let credential = credential {
                Auth.auth().signIn(with: credential) { (authResult, error) in
                    if let authResult = authResult {
                        callback(.authenticated(APIUser(user: authResult.user)))
                    } else {
                        log.error(error?.localizedDescription ?? "unable to sign in to firebase with apple")
                        callback(.failed(.appleError))
                    }
                }
            } else {
                callback(.failed(.appleError))
            }
        }
    }

    func verifyNumber(id: String, code: String, callback: @escaping Callback) {
        let credential = PhoneAuthProvider.provider().credential(withVerificationID: id, verificationCode: code)
        Auth.auth().signIn(with: credential) { (authResult, error) in
            if let error = error {
                self.log.error(error.localizedDescription)
                callback(.failed(.verificationCodeError))
            } else {
                callback(.authenticated(APIUser(user: authResult!.user)))
            }
        }
    }

    func verify(email: String, withLink verificationLink: URL, callback: @escaping Callback) {
        Auth.auth().signIn(withEmail: email, link: verificationLink.absoluteString) { (authResult, error) in
            if let authResult = authResult {
                callback(.authenticated(APIUser(user: authResult.user)))
            } else {
                self.log.error(error?.localizedDescription ?? "Unable to sign in with email")
                callback(.failed(.emailVerificationError))
            }
        }
    }

    func linkNumber(id: String, code: String, toUser user: APIUser, api: LoginAPI?, callback: @escaping ClosureBool) {
        let credential = PhoneAuthProvider.provider().credential(withVerificationID: id, verificationCode: code)
        user.user.link(with: credential) { (authResult, error) in
            if let _ = authResult {
                callback(true)
                api?.updateContactDetails()
            } else {
                self.log.error(error?.localizedDescription ?? "unknown error linking number to user")
                callback(false)
            }
        }
    }

    func link(email: String, withLink verificationLink: URL, toUser user: APIUser, api: LoginAPI?, callback: @escaping ClosureBool) {
        let credential = EmailAuthProvider.credential(withEmail: email, link: verificationLink.absoluteString)
        user.user.link(with: credential) { (authResult, error) in
            if let _ = authResult {
                callback(true)
                api?.updateContactDetails()
            } else {
                self.log.error(error?.localizedDescription ?? "unknown error linking number to user")
                callback(false)
            }
        }
    }

    @available(iOS 13, *)
    func linkApple(toUser user: APIUser, api: LoginAPI?, presentingController: ASAuthorizationControllerPresentationContextProviding, callback: @escaping ClosureBool) {
        signInWithApple(presentingController: presentingController) { [log] credential in
            if let credential = credential {
                user.user.link(with: credential) { (_, error) in
                    if let error = error {
                        log.error(error.localizedDescription)
                        callback(false)
                    } else {
                        callback(true)
                        api?.updateContactDetails()
                    }
                }
            } else {
                callback(false)
            }
        }
    }

    func unlinkEmail(from user: APIUser, api: LoginAPI?, callback: @escaping ClosureBool) {
        precondition(user.phoneNumber != nil || user.appleID != nil)
        user.user.unlink(fromProvider: EmailAuthProviderID) { [log] _, error in
            if let error = error {
                log.error(error.localizedDescription)
                callback(false)
            } else {
                callback(true)
                api?.updateContactDetails()
            }
        }
    }

    func unlinkNumber(from user: APIUser, api: LoginAPI?, callback: @escaping ClosureBool) {
        precondition(user.email != nil || user.appleID != nil)
        user.user.unlink(fromProvider: PhoneAuthProviderID) { [log] _, error in
            if let error = error {
                log.error(error.localizedDescription)
                callback(false)
            } else {
                callback(true)
                api?.updateContactDetails()
            }
        }
    }

    func unlinkApple(from user: APIUser, api: LoginAPI?, callback: @escaping ClosureBool) {
        precondition(user.phoneNumber != nil || user.email != nil)
        user.user.unlink(fromProvider: "apple.com") { [log] _, error in
            if let error = error {
                log.error(error.localizedDescription)
                callback(false)
            } else {
                callback(true)
                api?.updateContactDetails()
            }
        }
    }
}

@available(iOS 13.0, *)
extension LoginLogicController {
    class AppleAuthContext: NSObject, ASAuthorizationControllerDelegate {
        var callback: ((ASAuthorization?, Error?) -> Void)?

        func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
            callback?(authorization, nil)
        }

        func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
            callback?(nil, error)
        }
    }

    private func signInWithApple(presentingController: ASAuthorizationControllerPresentationContextProviding, callback: @escaping (AuthCredential?) -> Void) {
        var nonce: String!
        var bytes = [UInt8](repeating: 0, count: 32)
        let result = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if result == errSecSuccess {
            nonce = Data(bytes: &bytes, count: bytes.count).toHexString()
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.email]
            request.nonce = nonce.sha256()

            appleAuthContext.callback = { [log] authorization, error in
                guard let authorization = authorization else {
                    log.error(error?.localizedDescription ?? "failed to sign in with apple")
                    callback(nil)
                    return
                }
                guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                    log.error("unrecognised credential type – credentialType: \(String(describing: authorization.credential.self))")
                    callback(nil)
                    return
                }
                guard let appleIDToken = appleIDCredential.identityToken else {
                    log.error("unable to fetch identity token")
                    callback(nil)
                    return
                }
                guard let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
                    log.error("unable to serialize token string from data – tokenDebug: \(appleIDToken.debugDescription)")
                    callback(nil)
                    return
                }
                callback(OAuthProvider.credential(withProviderID: "apple.com", idToken: idTokenString, rawNonce: nonce))
            }

            let authorizationController = ASAuthorizationController(authorizationRequests: [request])
            authorizationController.delegate = appleAuthContext
            authorizationController.presentationContextProvider = presentingController
            authorizationController.performRequests()
        } else {
            log.error(String(describing: result))
            callback(nil)
        }
    }
}
