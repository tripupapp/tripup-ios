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

class ServerUpgrader {
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
    var object: Any?    // generic object, use to hold a strong reference for subtasks

    let log = Logger.self

    func upgrade(fromSchemaVersion currentSchemaVersion: String?, callback: @escaping ClosureBool) {
        switch currentSchemaVersion {
        case .none, "0":
            upgradeFromSchema0(callback: callback)
        default:
            fatalError("unimplemented schema: \(String(describing: currentSchemaVersion))")
        }
    }

    func upgradeClient() {

    }
}
