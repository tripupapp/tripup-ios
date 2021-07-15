//
//  ServerUpgrader.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 20/12/2020.
//  Copyright © 2020 Vinoth Ramiah. All rights reserved.
//

import Foundation

protocol UpgraderAPI: GroupAPI {
    func getSchema0Data(callbackOn queue: DispatchQueue, resultHandler: @escaping (Bool, [[String: Any]]?) -> Void)
    func patchSchema0Data(assetKeys: [String: String], assetMD5s: [String: String], callbackOn queue: DispatchQueue, resultHandler: @escaping ClosureBool)
}

class UpgradeOperation: AsynchronousOperation {
    var progressUpdateUI: ((_ completed: Int, _ total: Int) -> Void)?
    var progress = (completed: 0, total: 0) {
        didSet {
            progressUpdateUI?(progress.completed, progress.total)
        }
    }

    var user: User?
    var userKey: CryptoPrivateKey?
    var keychain: Keychain<CryptoPublicKey, CryptoPrivateKey>?
    var database: Database?
    var api: API?
    var dataService: DataService?
    var success: Bool = false

    let log = Logger.self

    override func main() {
        fatalError("unimplemented")
    }

    func finish(success: Bool) {
        self.success = success
        super.finish()
    }
}
