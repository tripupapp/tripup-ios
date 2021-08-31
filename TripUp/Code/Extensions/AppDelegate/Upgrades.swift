//
//  Upgrades.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 31/08/2021.
//  Copyright © 2021 Vinoth Ramiah. All rights reserved.
//

import Foundation
import UIKit

extension AppDelegate {
    func clientUpgradeOperationStarted(from previousVersion: String, to currentVersion: String) -> Bool {
        // reset local app data for legacy versions (<1.0) and versions prior to this fix (<=1.0.0.13)
        guard previousVersion.isHigherVersionNumberThan("1.0.0.13") else {
            presentNextRootViewController(resetApp: true)
            return true
        }

        let clientUpgradeSuccessfulBlock = { (version: String) in
            // refresh privacy policy
            self.privacyPolicyLoader = WebDocumentLoader(document: Globals.Documents.privacyPolicy)

            // finally, update local app version number
            UserDefaults.standard.set(version, forKey: UserDefaultsKey.AppVersionNumber.rawValue)
        }

        guard previousVersion.isHigherVersionNumberThan("1.1.2.4") else {
            let upgradeVC = UIStoryboard(name: "Login", bundle: nil).instantiateViewController(withIdentifier: "upgrade") as! UpgradeVC
            guard let primaryUserKey = try? keychain.retrievePrivateKey(withFingerprint: primaryUser!.fingerprint, keyType: .user) else {
                fatalError("primary user key not found")
            }
            let md5FixerOperation = MD5FixerOperation()
            md5FixerOperation.database = database
            md5FixerOperation.dataService = dataService
            md5FixerOperation.api = api
            md5FixerOperation.user = primaryUser
            md5FixerOperation.userKey = primaryUserKey
            md5FixerOperation.keychain = keychain
            md5FixerOperation.completionBlock = {
                DispatchQueue.main.async {
                    if md5FixerOperation.success {
                        clientUpgradeSuccessfulBlock("1.1.2.5")
                        self.presentNextRootViewController(after: upgradeVC)
                    } else {
                        let alert = UIAlertController(title: "Upgrade failed", message: "There was an error upgrading your data. Please try again. If the problem persists, please contact us.", preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in
                            self.presentNextRootViewController(after: upgradeVC)
                        }))
                        upgradeVC.present(alert, animated: true, completion: nil)
                    }
                }
            }
            upgradeVC.upgradeOperation = md5FixerOperation
            loginNavigationController(navigateTo: upgradeVC)
            return true
        }

        guard previousVersion.isHigherVersionNumberThan("1.1.2.16") else {
            let upgradeVC = UIStoryboard(name: "Login", bundle: nil).instantiateViewController(withIdentifier: "upgrade") as! UpgradeVC
            guard let primaryUserKey = try? keychain.retrievePrivateKey(withFingerprint: primaryUser!.fingerprint, keyType: .user) else {
                fatalError("primary user key not found")
            }
            let localDuplicateCleanupOperation = LocalDuplicateCleanupOperation()
            localDuplicateCleanupOperation.database = database
            localDuplicateCleanupOperation.dataService = dataService
            localDuplicateCleanupOperation.api = api
            localDuplicateCleanupOperation.user = primaryUser
            localDuplicateCleanupOperation.userKey = primaryUserKey
            localDuplicateCleanupOperation.keychain = keychain
            localDuplicateCleanupOperation.completionBlock = {
                DispatchQueue.main.async {
                    if localDuplicateCleanupOperation.success {
                        clientUpgradeSuccessfulBlock("1.1.2.17")
                        self.presentNextRootViewController(after: upgradeVC)
                    } else {
                        let alert = UIAlertController(title: "Upgrade failed", message: "There was an error upgrading your data. Please try again. If the problem persists, please contact us.", preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in
                            self.presentNextRootViewController(after: upgradeVC)
                        }))
                        upgradeVC.present(alert, animated: true, completion: nil)
                    }
                }
            }
            upgradeVC.upgradeOperation = localDuplicateCleanupOperation
            loginNavigationController(navigateTo: upgradeVC)
            return true
        }

        guard previousVersion.isHigherVersionNumberThan("2.1.3.1") else {
            let upgradeVC = UIStoryboard(name: "Login", bundle: nil).instantiateViewController(withIdentifier: "upgrade") as! UpgradeVC
            guard let primaryUserKey = try? keychain.retrievePrivateKey(withFingerprint: primaryUser!.fingerprint, keyType: .user) else {
                fatalError("primary user key not found")
            }
            let importOriginalFilenameOperation = ImportOriginalFilenameOperation()
            importOriginalFilenameOperation.database = database
            importOriginalFilenameOperation.dataService = dataService
            importOriginalFilenameOperation.api = api
            importOriginalFilenameOperation.user = primaryUser
            importOriginalFilenameOperation.userKey = primaryUserKey
            importOriginalFilenameOperation.keychain = keychain
            importOriginalFilenameOperation.completionBlock = {
                DispatchQueue.main.async {
                    if importOriginalFilenameOperation.success {
                        clientUpgradeSuccessfulBlock(currentVersion)    // NOTE: don't forget to hard code string if new case is entered later!
                        self.presentNextRootViewController(after: upgradeVC)
                    } else {
                        let alert = UIAlertController(title: "Upgrade failed", message: "There was an error upgrading your data. Please try again. If the problem persists, please contact us.", preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in
                            self.presentNextRootViewController(after: upgradeVC)
                        }))
                        upgradeVC.present(alert, animated: true, completion: nil)
                    }
                }
            }
            upgradeVC.upgradeOperation = importOriginalFilenameOperation
            loginNavigationController(navigateTo: upgradeVC)
            return true
        }

        clientUpgradeSuccessfulBlock(currentVersion)
        return false
    }
}
