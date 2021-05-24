//
//  Assert+Precondition.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 01/09/2020.
//  Copyright © 2020 Vinoth Ramiah. All rights reserved.
//

import Foundation

enum DispatchPredicateOptional {
    case on(DispatchQueue?)
    case onAsBarrier(DispatchQueue?)
    case notOn(DispatchQueue?)
}

func assert(_ dispatchPredicate: DispatchPredicateOptional) {
    #if DEBUG
    check(dispatchPredicate)
    #endif
}

func precondition(_ dispatchPredicate: DispatchPredicateOptional) {
    check(dispatchPredicate)
}

private func check(_ dispatchPredicate: DispatchPredicateOptional) {
    switch dispatchPredicate {
    case .notOn(.some(let queue)):
        dispatchPrecondition(condition: .notOnQueue(queue))
    case .on(.some(let queue)):
        dispatchPrecondition(condition: .onQueue(queue))
    case .onAsBarrier(.some(let queue)):
        dispatchPrecondition(condition: .onQueueAsBarrier(queue))
    case .notOn(.none), .on(.none), .onAsBarrier(.none):
        break
    }
}
