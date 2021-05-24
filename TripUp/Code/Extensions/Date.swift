//
//  Date.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 10/08/2017.
//  Copyright © 2017 Vinoth Ramiah. All rights reserved.
//

import Foundation

extension Date {
    init?(iso8601 dateString: String) {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: dateString) else { return nil }
        self = date
    }

    var iso8601: String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: self)
    }
}
