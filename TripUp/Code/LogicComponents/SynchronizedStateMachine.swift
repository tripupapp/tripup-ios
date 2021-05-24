//
//  SynchronizedStateMachine.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 01/03/2021.
//  Copyright © 2021 Vinoth Ramiah. All rights reserved.
//

import Foundation
import GameplayKit.GKStateMachine

class SynchronizedStateMachine: GKStateMachine {
    private let dispatchQueue: DispatchQueue = DispatchQueue(label: String(describing: SynchronizedStateMachine.self))

    override var currentState: GKState? {
        precondition(.on(dispatchQueue))
        return super.currentState
    }

    var currentStateSynced: GKState? {
        dispatchQueue.sync {
            return currentState
        }
    }

    @discardableResult override func enter(_ stateClass: AnyClass) -> Bool {
        dispatchQueue.sync {
            return super.enter(stateClass)
        }
    }
}
