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
import Firebase
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
    case authenticated
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
    private(set) var authenticatedUser: AuthenticatedUser?

    private let log = Logger.self
    private let emailAuthenticationFallbackURL: URL

    @available(iOS 13.0, *)
    private lazy var appleAuthContext = AppleAuthContext()

    init(emailAuthenticationFallbackURL: URL) {
        self.emailAuthenticationFallbackURL = emailAuthenticationFallbackURL
    }
}

extension LoginLogicController {
    func initialize() {
        FirebaseApp.configure()
        if let firebaseUser = Auth.auth().currentUser {
            authenticatedUser = AuthenticatedUser(firebaseAuthUser: firebaseUser)
        }
    }
    
    func signOutAuthenticatedUser() {
        do {
            try Auth.auth().signOut()
        } catch {
            log.error(String(describing: error))
            fatalError(String(describing: error))
        }
        precondition(Thread.isMainThread)
        authenticatedUser = nil
    }
}

extension LoginLogicController {
    func isMagicSignInLink(_ link: URL) -> Bool {
        return Auth.auth().isSignIn(withEmailLink: link.absoluteString)
    }

    func login(withNumber number: String, callback: @escaping Callback) {
        PhoneAuthProvider.provider().verifyPhoneNumber(number, uiDelegate: nil) { (verificationID, error) in
            if let error = error {
                self.log.error(error.localizedDescription)
                callback(.failed(.phoneNumberError))
            } else {
                callback(.pendingNumberVerification(number, verificationID!))
            }
        }
    }

    func login(withEmail email: String, callback: @escaping Callback) {
        let actionCodeSettings = ActionCodeSettings()
        actionCodeSettings.url = emailAuthenticationFallbackURL
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
        signInWithApple(presentingController: presentingController) { [weak self] credential in
            if let credential = credential {
                Auth.auth().signIn(with: credential) { (authResult, error) in
                    if let authResult = authResult {
                        precondition(Thread.isMainThread)
                        self?.authenticatedUser = AuthenticatedUser(firebaseAuthUser: authResult.user)
                        callback(.authenticated)
                    } else {
                        self?.log.error(String(describing: error ?? "unable to sign in with apple"))
                        callback(.failed(.appleError))
                    }
                }
            } else {
                callback(.failed(.appleError))
            }
        }
    }

    func verifyNumber(id: String, withCode code: String, callback: @escaping Callback) {
        let credential = PhoneAuthProvider.provider().credential(withVerificationID: id, verificationCode: code)
        Auth.auth().signIn(with: credential) { (authResult, error) in
            if let authResult = authResult {
                precondition(Thread.isMainThread)
                self.authenticatedUser = AuthenticatedUser(firebaseAuthUser: authResult.user)
                callback(.authenticated)
            } else {
                self.log.error(String(describing: error ?? "unable to verify number"))
                callback(.failed(.verificationCodeError))
            }
        }
    }

    func verify(email: String, withLink verificationLink: URL, callback: @escaping Callback) {
        Auth.auth().signIn(withEmail: email, link: verificationLink.absoluteString) { (authResult, error) in
            if let authResult = authResult {
                precondition(Thread.isMainThread)
                self.authenticatedUser = AuthenticatedUser(firebaseAuthUser: authResult.user)
                callback(.authenticated)
            } else {
                self.log.error(String(describing: error ?? "unable to verify email"))
                callback(.failed(.emailVerificationError))
            }
        }
    }

    func linkNumber(id: String, verificationCode: String, api: LoginAPI?, callback: @escaping ClosureBool) {
        let credential = PhoneAuthProvider.provider().credential(withVerificationID: id, verificationCode: verificationCode)
        authenticatedUser?.firebaseAuthUser.link(with: credential) { [weak self] (authResult, error) in
            if let _ = authResult {
                callback(true)
                api?.updateContactDetails()
            } else {
                self?.log.error(error?.localizedDescription ?? "unknown error linking number to user")
                callback(false)
            }
        }
    }

    func link(email: String, verificationLink: URL, api: LoginAPI?, callback: @escaping ClosureBool) {
        let credential = EmailAuthProvider.credential(withEmail: email, link: verificationLink.absoluteString)
        authenticatedUser?.firebaseAuthUser.link(with: credential) { [weak self] (authResult, error) in
            if let _ = authResult {
                callback(true)
                api?.updateContactDetails()
            } else {
                self?.log.error(error?.localizedDescription ?? "unknown error linking number to user")
                callback(false)
            }
        }
    }

    @available(iOS 13, *)
    func linkApple(api: LoginAPI?, presentingController: ASAuthorizationControllerPresentationContextProviding, callback: @escaping ClosureBool) {
        signInWithApple(presentingController: presentingController) { [weak self] credential in
            if let credential = credential {
                self?.authenticatedUser?.firebaseAuthUser.link(with: credential) { [weak self] (_, error) in
                    if let error = error {
                        self?.log.error(error.localizedDescription)
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

    func unlinkEmail(api: LoginAPI?, callback: @escaping ClosureBool) {
        if let authenticatedUser = authenticatedUser {
            precondition(authenticatedUser.phoneNumber != nil || authenticatedUser.appleID != nil)
            authenticatedUser.firebaseAuthUser.unlink(fromProvider: EmailAuthProviderID) { [weak self] _, error in
                if let error = error {
                    self?.log.error(error.localizedDescription)
                    callback(false)
                } else {
                    callback(true)
                    api?.updateContactDetails()
                }
            }
        } else {
            assertionFailure()
            callback(false)
        }
    }

    func unlinkNumber(api: LoginAPI?, callback: @escaping ClosureBool) {
        if let authenticatedUser = authenticatedUser {
            precondition(authenticatedUser.email != nil || authenticatedUser.appleID != nil)
            authenticatedUser.firebaseAuthUser.unlink(fromProvider: PhoneAuthProviderID) { [weak self] _, error in
                if let error = error {
                    self?.log.error(error.localizedDescription)
                    callback(false)
                } else {
                    callback(true)
                    api?.updateContactDetails()
                }
            }
        } else {
            assertionFailure()
            callback(false)
        }
    }

    func unlinkApple(api: LoginAPI?, callback: @escaping ClosureBool) {
        if let authenticatedUser = authenticatedUser {
            precondition(authenticatedUser.phoneNumber != nil || authenticatedUser.email != nil)
            authenticatedUser.firebaseAuthUser.unlink(fromProvider: "apple.com") { [log] _, error in
                if let error = error {
                    log.error(error.localizedDescription)
                    callback(false)
                } else {
                    callback(true)
                    api?.updateContactDetails()
                }
            }
        } else {
            assertionFailure()
            callback(false)
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
