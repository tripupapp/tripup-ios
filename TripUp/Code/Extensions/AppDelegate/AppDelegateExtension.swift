//
//  AppDelegateExtension.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 15/08/2019.
//  Copyright © 2019 Vinoth Ramiah. All rights reserved.
//

import Foundation

import AlamofireNetworkActivityIndicator
import FTLinearActivityIndicator
import Firebase

import TripUpShared

protocol AppDelegateExtension: AnyObject {
    var autoBackup: Bool? { get set }
    func initialise(_ cloudStorageVC: CloudStorageVC)
    func presentNextRootViewController(after currentViewController: UIViewController?, fadeIn: Bool, resetApp: Bool)
    func userCredentials(from authenticatedUser: AuthenticatedUser, callback: @escaping LoginLogicController.Callback)
}

extension AppDelegateExtension {
    func presentNextRootViewController(after currentViewController: UIViewController?, fadeIn: Bool = false, resetApp: Bool = false) {
        presentNextRootViewController(after: currentViewController, fadeIn: fadeIn, resetApp: resetApp)
    }
}

extension AppDelegate {
    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        guard let url = userActivity.webpageURL else {
            return false
        }
        if let loginNavVC = window?.rootViewController as? LoginNavigationController, let loginVC = loginNavVC.viewControllers.first as? LoginView, loginVC.handle(link: url) {
            return true
        } else if let mainVC = window?.rootViewController as? MainVC, let authVC = (mainVC.viewControllers?.last as? UINavigationController)?.visibleViewController as? AuthenticationView, authVC.handle(link: url) {
            return true
        } else if let context = context {
            return context.handle(url: url)
        } else {
            return false
        }
    }
    
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        // userInfo["custom"]["a"] is equivalent to OneSignals additionalData dictionary
        guard let custom = userInfo["custom"] as? [AnyHashable: Any], let a = custom["a"] as? [AnyHashable: Any] else {
            completionHandler(.noData)
            return
        }
        guard let notificationString = a["signal"] as? String, let notificationType = UserNotificationType(rawValue: notificationString) else {
            completionHandler(.noData)
            return
        }
        var groupID: UUID?
        if let groupIDstring = a["groupid"] as? String {
            groupID = UUID(uuidString: groupIDstring)
        }
        let notification = UserNotification(type: notificationType, groupID: groupID)

        // fulfill requirement to call handler within 30 seconds
        let dispatchQueue = DispatchQueue.global()
        var incomplete = true
        context?.receive(notification, completion: { (success) in
            dispatchQueue.async {
                if incomplete {
                    completionHandler(success ? .newData : .failed)
                    incomplete = false
                }
            }
        })
        dispatchQueue.asyncAfter(deadline: .now() + 25) {
            if incomplete {
                completionHandler(.failed)
                incomplete = false
            }
        }
    }

    func setup() {
        // configure Logger
        Logger.configure(with: config)
        
        // firebase initialisation
        FirebaseApp.configure()

        // configure database – handles schema changes automatically
        database.configure()

        // configure Keyboard
        Keyboard.shared.enabled = true

        // configure Alamofire calls to use network activity indicator in status bar
        NetworkActivityIndicatorManager.shared.isEnabled = true

        // linear network indicator for iPhone X and above
        UIApplication.configureLinearNetworkActivityIndicatorIfNeeded()

        // configure universal links singleton
        UniversalLinksService.shared.appStoreID = config.appStoreID
        UniversalLinksService.shared.domain = config.domain
        UniversalLinksService.shared.dynamicLinksDomain = config.firebaseDynamicLinksDomain

        do {
            try resetTmpDir()
            try createTripUpDirs()
        } catch {
            fatalError(String(describing: error))
        }
    }

    func clearAppData() {
        userNotificationProvider?.signOut()
        do {
            try resetTripUpDirs()
            try resetTmpDir()
        } catch {
            fatalError(String(describing: error))
        }
        database.clear()
        purchasesController.signOut()
        if let awsAdapter = dataService as? AWSAdapter {
            awsAdapter.signOut()
        }
        authenticatedUser = nil
        context = nil
        try? keychain.clear()
        UserDefaults.standard.dictionaryRepresentation().keys.forEach {
            UserDefaults.standard.removeObject(forKey: $0)
        }
        log.deleteLogFile()
        #if DEBUG
        log.setDebugLevel(on: true)
        #else
        log.setDebugLevel(on: false)
        #endif
    }

    private func createTripUpDirs() throws {
        try FileManager.default.createDirectory(at: Globals.Directories.legal, withIntermediateDirectories: true, attributes: nil)
        try FileManager.default.createDirectory(at: Globals.Directories.assetsLow, withIntermediateDirectories: true, attributes: nil)
        try FileManager.default.createDirectory(at: Globals.Directories.assetsOriginal, withIntermediateDirectories: true, attributes: nil)

        // exclude assetsLow directory from backups (not needed for others as we either want to preserve backup or they are already stored in excluded directories)
        var assetsLow = Globals.Directories.assetsLow
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try assetsLow.setResourceValues(resourceValues)
    }

    private func resetTripUpDirs() throws {
        try FileManager.default.removeItem(at: Globals.Directories.legal)
        try FileManager.default.removeItem(at: Globals.Directories.assetsLow)
        try FileManager.default.removeItem(at: Globals.Directories.assetsOriginal)
        try createTripUpDirs()
    }

    private func resetTmpDir() throws {
        try FileManager.default.removeItem(at: Globals.Directories.tmp)
        try FileManager.default.createDirectory(at: Globals.Directories.tmp, withIntermediateDirectories: true, attributes: nil)
    }

    func lowDiskSpace(callback: @escaping ClosureBool) {
        DispatchQueue.global().async {
            if let resourceValues = try? Globals.Directories.SandboxRoot.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]), let freeSpace = resourceValues.volumeAvailableCapacityForImportantUsage {
                DispatchQueue.main.async {
                    callback(freeSpace < 524288000) // 500 MB local storage
                }
            } else {
                DispatchQueue.main.async {
                    callback(true)
                }
            }
        }
    }
}

extension AppDelegate: AppDelegateExtension {
    var primaryUser: User? {
        get {
            guard let primaryUserEncoded = UserDefaults.standard.data(forKey: UserDefaultsKey.PrimaryUser.rawValue) else { return nil }
            let decoder = JSONDecoder()
            return try? decoder.decode(User.self, from: primaryUserEncoded)
        }
        set {
            if let primaryUser = newValue {
                let encoder = JSONEncoder()
                let primaryUserEncoded = try! encoder.encode(primaryUser)
                UserDefaults.standard.set(primaryUserEncoded, forKey: UserDefaultsKey.PrimaryUser.rawValue)
                log.info("saving \(UserDefaultsKey.PrimaryUser.rawValue) to UserDefaults")
            } else {
                UserDefaults.standard.removeObject(forKey: UserDefaultsKey.PrimaryUser.rawValue)
                log.info("removing \(UserDefaultsKey.PrimaryUser.rawValue) from UserDefaults")
            }
        }
    }

    var serverSchemaVersion: String? {
        get {
            return UserDefaults.standard.string(forKey: UserDefaultsKey.ServerSchemaVersion.rawValue)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: UserDefaultsKey.ServerSchemaVersion.rawValue)
        }
    }

    var autoBackup: Bool? {
        get {
            return UserDefaults.standard.object(forKey: UserDefaultsKey.AutoBackup.rawValue) as? Bool
        }
        set {
            UserDefaults.standard.set(newValue, forKey: UserDefaultsKey.AutoBackup.rawValue)
        }
    }

    private func fadeWindow(to viewController: UIViewController) {
        if let snapshot = window?.snapshotView(afterScreenUpdates: true) {
            viewController.view.addSubview(snapshot)
            window?.rootViewController = viewController

            UIView.animate(withDuration: 0.3, animations: {
                snapshot.layer.opacity = 0
                snapshot.layer.transform = CATransform3DMakeScale(1.5, 1.5, 1.5)
            }) { _ in
                snapshot.removeFromSuperview()
            }
        } else {
            window?.rootViewController = viewController
        }
    }

    func presentNextRootViewController(after currentViewController: UIViewController? = nil, fadeIn: Bool = false, resetApp: Bool = false) {
        // user logged in
        guard let authenticatedUser = authenticatedUser, let primaryUser = primaryUser, !resetApp else {
            clearAppData()
            privacyPolicyLoader = WebDocumentLoader(document: Globals.Documents.privacyPolicy)  // download privacy policy, for use in LoginView
            let loginVC = UIStoryboard(name: "Login", bundle: nil).instantiateViewController(withIdentifier: "loginvc") as! LoginView
            loginVC.appDelegateExtension = self
            loginVC.logicController = LoginLogicController(emailAuthenticationFallbackURL: URL(string: config.appStoreURL)!)
            loginNavigationController(navigateTo: loginVC, fadeIn: fadeIn)
            return
        }
        if !purchasesController.signedIn {
            purchasesController.signIn(userID: authenticatedUser.id)
        }
        if api.authenticatedUser == nil {
            api.authenticatedUser = authenticatedUser
        }
        guard let dataService = dataService else {
            fatalError()
        }
        if let awsAdapter = dataService as? AWSAdapter, awsAdapter.authenticatedUser == nil {
            awsAdapter.bucket = config.awsAssetsBucket
            awsAdapter.federationProviderName = config.federationProvider
            awsAdapter.region = config.awsAssetsBucketRegion
            awsAdapter.authenticatedUser = authenticatedUser
        }
        userNotificationProvider?.signIn(userID: primaryUser.uuid)

        // account password settings
        guard UserDefaults.standard.bool(forKey: UserDefaultsKey.PasswordBackupOption.rawValue) else {
            let securityView = UIStoryboard(name: "Security", bundle: nil).instantiateInitialViewController() as! SecurityView
            securityView.initialise(primaryUser: primaryUser, keychain: keychain)
            securityView.transparent = true
            securityView.navigationBarHidden = true
            securityView.nextAction = { [unowned self] in
                UserDefaults.standard.set(true, forKey: UserDefaultsKey.PasswordBackupOption.rawValue)
                self.presentNextRootViewController(after: securityView)
            }
            loginNavigationController(navigateTo: securityView)
            return
        }

        // server updates
        guard serverSchemaVersion == config.serverSchemaVersion else {
            // don't remove entire keychain! need to keep icloud data, primary user key, etc
            // don't remove all user defaults! some user defaults need to persist (e.g. primaryUser)
            // don't nil out authenticatedUser or purchasesController

            do {
                try resetTripUpDirs()
                try resetTmpDir()
            } catch {
                fatalError(String(describing: error))
            }
            database.clear()

            // finally, remove app version number; treat client as a new install
            UserDefaults.standard.removeObject(forKey: UserDefaultsKey.AppVersionNumber.rawValue)

            let upgradeVC = UIStoryboard(name: "Login", bundle: nil).instantiateViewController(withIdentifier: "upgrade") as! UpgradeVC
            switch serverSchemaVersion {
            case .none, "0":
                let schemaUpgradeOperation = Schema0to1UpgradeOperation()
                guard let primaryUserKey = try? keychain.retrievePrivateKey(withFingerprint: primaryUser.fingerprint, keyType: .user) else {
                    fatalError("primary user key not found")
                }
                schemaUpgradeOperation.userKey = primaryUserKey
                schemaUpgradeOperation.api = api
                schemaUpgradeOperation.dataService = dataService
                schemaUpgradeOperation.completionBlock = {
                    DispatchQueue.main.async {
                        if schemaUpgradeOperation.success {
                            self.serverSchemaVersion = "1"
                            self.presentNextRootViewController(after: upgradeVC)
                        } else {
                            let alert = UIAlertController(title: "Upgrade failed", message: "There was an error upgrading your data. Please try again. If the problem persists, please contact us.", preferredStyle: .alert)
                            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in
                                self.presentNextRootViewController(after: upgradeVC, resetApp: true)
                            }))
                            upgradeVC.present(alert, animated: true, completion: nil)
                        }
                    }
                }
                upgradeVC.upgradeOperation = schemaUpgradeOperation
            default:
                fatalError("unimplemented schema: \(String(describing: serverSchemaVersion))")
            }
            loginNavigationController(navigateTo: upgradeVC)
            return
        }

        // auto backup selection
        guard autoBackup != nil else {
            let backupVC = UIStoryboard(name: "Login", bundle: nil).instantiateViewController(withIdentifier: "backupprefs") as! BackupPreferencesVC
            backupVC.appDelegateExtension = self
            loginNavigationController(navigateTo: backupVC)
            return
        }

        // client updates
        let currentVersion = config.appVersion
        if let previousVersion = UserDefaults.standard.string(forKey: UserDefaultsKey.AppVersionNumber.rawValue) {  // existing install
            if previousVersion != currentVersion {
                log.info("migrating from \(previousVersion) to \(currentVersion)")

                // reset local app data for legacy versions (<1.0) and versions prior to this fix (<=1.0.0.13)
                guard previousVersion.isHigherVersionNumberThan("1.0.0.13") else {
                    presentNextRootViewController(resetApp: true)
                    return
                }

                let clientUpgradeSuccessfulBlock = { (version: String) in
                    // refresh privacy policy
                    self.privacyPolicyLoader = WebDocumentLoader(document: Globals.Documents.privacyPolicy)

                    // finally, update local app version number
                    UserDefaults.standard.set(version, forKey: UserDefaultsKey.AppVersionNumber.rawValue)
                }

                guard previousVersion.isHigherVersionNumberThan("1.1.2.4") else {
                    let upgradeVC = UIStoryboard(name: "Login", bundle: nil).instantiateViewController(withIdentifier: "upgrade") as! UpgradeVC
                    guard let primaryUserKey = try? keychain.retrievePrivateKey(withFingerprint: primaryUser.fingerprint, keyType: .user) else {
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
                    return
                }

                guard previousVersion.isHigherVersionNumberThan("1.1.2.16") else {
                    let upgradeVC = UIStoryboard(name: "Login", bundle: nil).instantiateViewController(withIdentifier: "upgrade") as! UpgradeVC
                    guard let primaryUserKey = try? keychain.retrievePrivateKey(withFingerprint: primaryUser.fingerprint, keyType: .user) else {
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
                    upgradeVC.upgradeOperation = localDuplicateCleanupOperation
                    loginNavigationController(navigateTo: upgradeVC)
                    return
                }

                clientUpgradeSuccessfulBlock(currentVersion)
            }
        } else {    // new install
            // download privacy policy – in case it was wiped from previous clearing of app data
            privacyPolicyLoader = WebDocumentLoader(document: Globals.Documents.privacyPolicy)

            // set local app version number
            UserDefaults.standard.set(currentVersion, forKey: UserDefaultsKey.AppVersionNumber.rawValue)
        }

        context = AppContext(user: primaryUser, authenticatedUser: authenticatedUser, webAPI: api, keychain: keychain, database: database, config: config, purchasesController: purchasesController, dataService: dataService, appDelegate: self)
        userNotificationProvider?.receiver = context
        
        let mainVC = UIStoryboard(name: "Main", bundle: nil).instantiateInitialViewController() as! MainVC
        context!.initialise(mainVC)

        if currentViewController == nil {
            window?.rootViewController = mainVC
        } else {
            fadeWindow(to: mainVC)
        }

        if UIApplication.shared.applicationState != .background {
            context?.networkMonitor?.refresh()  // trigger context update
            notificationPermissionPromptWithDelay()
        }
    }

    func notificationPermissionPromptWithDelay() {
        guard userNotificationProvider?.notificationPermisssionUndetermined == .some(true) else {
            return
        }
        // TODO: call async after mainVC has loaded
        // delay to space things out a bit
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            let notificationPrerequest = UIAlertController(title: "Enable Push Notifications", message: "Notifications are required to see real-time updates to shared albums", preferredStyle: .alert)
            let enableAction = UIAlertAction(title: "Allow Notifications", style: .default) { [weak self] (_) in
                self?.userNotificationProvider?.promptForPermission()
            }
            let maybeLaterAction = UIAlertAction(title: "Maybe Later", style: .cancel, handler: nil)
            notificationPrerequest.addAction(enableAction)
            notificationPrerequest.addAction(maybeLaterAction)
            self.window?.rootViewController?.present(notificationPrerequest, animated: true, completion: nil)
        }
    }

    func initialise(_ cloudStorageVC: CloudStorageVC) {
        cloudStorageVC.initialise(purchasesController: purchasesController)
    }

    private func loginNavigationController(navigateTo viewController: UIViewController, fadeIn: Bool = false) {
        if let loginNavigationController = window?.rootViewController as? LoginNavigationController {
            loginNavigationController.setViewControllers([viewController], animated: true)
        } else {
            let loginNavigationController = UIStoryboard(name: "Login", bundle: nil).instantiateInitialViewController() as! LoginNavigationController
            loginNavigationController.setViewControllers([viewController], animated: false)
            if fadeIn {
                fadeWindow(to: loginNavigationController)
            } else {
                window?.rootViewController = loginNavigationController
            }
        }
    }
}

extension AppDelegate {
    func userCredentials(from authenticatedUser: AuthenticatedUser, callback: @escaping LoginLogicController.Callback) {
        api.authenticatedUser = authenticatedUser
        api.getUUID(callbackOn: .main) { [unowned self] success, userData in
            guard success else { callback(.failed(.apiError)); return }
            if let userData = userData {
                self.log.info("existing user found on server with id: \(userData.uuid.string)")

                if let password = try? self.keychain.retrieveFromiCloud(lookupKey: userData.uuid.string), let key = try? CryptoPrivateKey(key: userData.privateKey, password: password, for: .user) {
                    self.log.debug("password retrieved from iCloud keychain")
                    self.saveLoginDetails(userID: userData.uuid, userSchemaVersion: userData.schemaVersion, userKey: key, authenticatedUser: authenticatedUser)
                    callback(.loggedIn)
                } else {
                    self.log.debug("password not available. Request from user...")
                    callback(.passwordRequired({ [unowned self] password -> Bool in
                        if let key = self.createAndUnlock(privateKey: userData.privateKey, with: password) {
                            self.saveLoginDetails(userID: userData.uuid, userSchemaVersion: userData.schemaVersion, userKey: key, authenticatedUser: authenticatedUser)
                            return true
                        }
                        return false
                    }))
                }
            } else {
                self.log.info("no id found, creating new user")

                let userKey = self.keychain.generateNewPrivateKey(.user, passwordProtected: true, saveToKeychain: false)
                self.api.createUser(publicKey: userKey.public, privateKey: userKey.private, callbackOn: .main) { [unowned self] success, uuid in
                    if success, let uuid = uuid {
                        do {
                            try self.keychain.saveToiCloud(userKey.password!, lookupKey: uuid.string)
                        } catch {
                            fatalError("\(error)")
                        }
                        self.saveLoginDetails(userID: uuid, userSchemaVersion: self.config.serverSchemaVersion, userKey: userKey, authenticatedUser: authenticatedUser)
                        callback(.loggedIn)
                    } else {
                        callback(.failed(.apiError))
                    }
                }
            }
        }
    }

    private func createAndUnlock(privateKey: String, with password: String) -> CryptoPrivateKey? {
        do {
            return try CryptoPrivateKey(key: privateKey, password: password, for: .user)
        } catch let error as KeyConstructionError where error == .passwordRequiredForKey || error == .invalidPasswordForKey {
            log.warning("invalid password for user key")
        } catch {
            fatalError(String(describing: error))
        }
        return nil
    }

    private func saveLoginDetails(userID: UUID, userSchemaVersion: String, userKey: CryptoPrivateKey, authenticatedUser: AuthenticatedUser) {
        do {
            try keychain.savePrivateKey(userKey)   // save to device keychain only
        } catch {
            fatalError(error.localizedDescription)
        }
        self.primaryUser = User(uuid: userID, fingerprint: userKey.fingerprint, localContact: nil)
        self.serverSchemaVersion = userSchemaVersion
        self.authenticatedUser = authenticatedUser
    }
}
