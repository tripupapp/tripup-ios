//
//  UInt64.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 23/03/2020.
//  Copyright © 2020 Vinoth Ramiah. All rights reserved.
//

import Foundation

extension UInt64 {
    init?(exactly value: Int64?) {
        guard let value = value else { return nil }
        self.init(exactly: value)
    }
}
