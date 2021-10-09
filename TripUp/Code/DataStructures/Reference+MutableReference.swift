//
//  Reference+MutableReference.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 08/10/2021.
//  Copyright © 2021 Vinoth Ramiah. All rights reserved.
//

// https://www.swiftbysundell.com/articles/combining-value-and-reference-types-in-swift/#passing-references-to-value-types

import Foundation

class Reference<Value> {
    fileprivate(set) var value: Value

    init(value: Value) {
        self.value = value
    }
}

class MutableReference<Value>: Reference<Value> {
    func update(with value: Value) {
        self.value = value
    }
}
