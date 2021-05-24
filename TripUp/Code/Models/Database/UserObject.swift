//
//  UserObject.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 30/09/2019.
//  Copyright © 2019 Vinoth Ramiah. All rights reserved.
//

import Foundation
import RealmSwift

@objcMembers final class UserObject: Object {
    dynamic var uuid: String = ""
    dynamic var fingerprint: String = ""
    dynamic var contact: Data? = nil

    override static func primaryKey() -> String? {
        return "uuid"
    }

    convenience init(_ user: User) {
        self.init()
        self.uuid = user.uuid.string
        self.fingerprint = user.fingerprint
        self.contact = try? JSONEncoder().encode(user.localContact)
    }
}

extension User {
    init(from object: UserObject) {
        self.init(
            uuid: UUID(uuidString: object.uuid)!,
            fingerprint: object.fingerprint,
            localContact: {
                if let contactData = object.contact {
                    return try? JSONDecoder().decode(Contact.self, from: contactData)
                }
                return nil
            }()
        )
    }
}
