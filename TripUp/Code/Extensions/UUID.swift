//
//  UUID.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 08/06/2017.
//  Copyright © 2017 Vinoth Ramiah. All rights reserved.
//

import Foundation

extension UUID {
    var string: String {
        return self.uuidString.lowercased()
    }
}

enum UUIDError: Error {
    case invalidString
}
