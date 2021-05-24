//
//  URL.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 21/12/2018.
//  Copyright © 2018 Vinoth Ramiah. All rights reserved.
//

import Foundation

extension URL {
    init?(optionalString: String?) {
        guard let string = optionalString else { return nil }
        self.init(string: string)
    }
}
