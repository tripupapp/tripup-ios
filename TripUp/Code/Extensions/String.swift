//
//  String.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 22/02/2019.
//  Copyright © 2019 Vinoth Ramiah. All rights reserved.
//

import Foundation

extension String: Error { }

extension String: LocalizedError {
    public var errorDescription: String? { return self }
}
