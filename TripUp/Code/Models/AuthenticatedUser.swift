//
//  AuthenticatedUser.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 06/02/2019.
//  Copyright © 2019 Vinoth Ramiah. All rights reserved.
//

import Foundation

import Firebase

struct APIToken: Equatable {
    let value: String
    let expirationDate: Date

    var notExpired: Bool {
        return expirationDate > Date()
    }
}

class AuthenticatedUser {
    var id: String {
        return firebaseAuthUser.uid
    }

    var phoneNumber: String? {
        return firebaseAuthUser.providerData.first(where: { $0.providerID == PhoneAuthProviderID })?.phoneNumber
    }

    var email: String? {
        return firebaseAuthUser.providerData.first(where: { $0.providerID == EmailAuthProviderID })?.email
    }

    var appleID: String? {
        return firebaseAuthUser.providerData.first(where: { $0.providerID == "apple.com" })?.email
    }

    let firebaseAuthUser: Firebase.User
    private let log = Logger.self

    init(firebaseAuthUser: Firebase.User) {
        self.firebaseAuthUser = firebaseAuthUser
    }

    func token(callback: @escaping (APIToken?) -> Void) {
        firebaseAuthUser.getIDTokenResult { [weak self] tokenResult, error in
            if let tokenResult = tokenResult {
                callback(APIToken(value: tokenResult.token, expirationDate: tokenResult.expirationDate))
            } else {
                self?.log.error(error!.localizedDescription)
                self?.log.debug(tokenResult.debugDescription)
                callback(nil)
            }
        }
    }
}
