//
//  User.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 13/03/2018.
//  Copyright © 2018 Vinoth Ramiah. All rights reserved.
//

import Foundation

struct User: Hashable {
    let uuid: UUID
    let fingerprint: String
    let localContact: Contact?

    init(uuid: UUID, fingerprint: String, localContact: Contact?) {
        self.uuid = uuid
        self.fingerprint = fingerprint
        self.localContact = localContact
    }
}

extension User: Codable {}

extension User: Comparable {
    static func < (lhs: User, rhs: User) -> Bool {
        if let lhsName = lhs.localContact?.name, let rhsName = rhs.localContact?.name, lhsName != rhsName {
            return lhsName < rhsName
        } else {
            return lhs.uuid.string < rhs.uuid.string
        }
    }
}
