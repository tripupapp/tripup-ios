//
//  AuthenticatedUser.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 06/02/2019.
//  Copyright © 2019 Vinoth Ramiah. All rights reserved.
//

import Foundation
import FirebaseAuth

struct APIToken: Equatable {
    let value: String
    let expirationDate: Date

    var notExpired: Bool {
        return expirationDate > Date()
    }
}

class AuthenticatedUser {
    private let auth = Auth.auth()
    let user: FirebaseAuth.User
    private let log = Logger.self

    var id: String {
        return user.uid
    }

    var phoneNumber: String? {
        return user.providerData.first(where: { $0.providerID == PhoneAuthProviderID })?.phoneNumber
    }

    var email: String? {
        return user.providerData.first(where: { $0.providerID == EmailAuthProviderID })?.email
    }

    var appleID: String? {
        return user.providerData.first(where: { $0.providerID == "apple.com" })?.email
    }

    // can only be initialised after FirebaseApp.configure()
    init?() {
        guard let user = auth.currentUser else { return nil }
        self.user = user
        token()
    }

    init(user: FirebaseAuth.User) {
        self.user = user
        token()
    }

    deinit {
        do {
            try auth.signOut()
        } catch {
            log.error(String(describing: error))
        }
    }

    func token(_ callback: ((APIToken?) -> Void)? = nil) {
        user.getIDTokenResult { tokenResult, error in
            if let tokenResult = tokenResult {
                callback?(APIToken(value: tokenResult.token, expirationDate: tokenResult.expirationDate))
            } else {
                self.log.error(error!.localizedDescription)
                self.log.debug(tokenResult.debugDescription)
                callback?(nil)
            }
        }
    }
}
