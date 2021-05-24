//
//  AtomicVar.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 10/12/2018.
//  Copyright © 2018 Vinoth Ramiah. All rights reserved.
//

import Foundation

class AtomicVar<T> {
    private let queue = DispatchQueue(label: "app.tripup.atomicvar.\(T.self)", qos: .default, attributes: .concurrent)
    private var value_: T
    var value: T {
        get {
            return queue.sync { self.value_ }
        }
    }

    init(_ value: T) {
        self.value_ = value
    }

    func mutate(_ transform: (inout T) -> ()) {
        queue.sync(flags: .barrier) {
            transform(&self.value_)
        }
    }
}
