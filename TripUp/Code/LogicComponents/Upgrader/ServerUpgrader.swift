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

    let dataManager: DataManager
    let userKey: CryptoPrivateKey
    let api: UpgraderAPI

    init(userKey: CryptoPrivateKey, api: UpgraderAPI, dataService: DataService) {
        self.dataManager = DataManager(dataService: dataService, simultaneousTransfers: 4)
        self.userKey = userKey
        self.api = api
    }

    func upgrade(fromSchemaVersion currentSchemaVersion: String?, callback: @escaping ClosureBool) {
        switch currentSchemaVersion {
        case .none, "0":
            upgradeFromSchema0(callback: callback)
        default:
            fatalError("unimplemented schema: \(String(describing: currentSchemaVersion))")
        }
    }
}
