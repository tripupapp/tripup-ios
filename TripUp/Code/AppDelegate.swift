//
//  AppDelegate.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 16/03/2017.
//  Copyright © 2017 Vinoth Ramiah. All rights reserved.
//

import UIKit

struct AppConfig {
    let apiBaseURL: String
    let appVersion: String
    let appStoreID: String
    let appStoreURL: String
    let awsAssetsBucket: String
    let awsAssetsBucketRegion: String
    let domain: String
    let federationProvider: String
    let firebaseDynamicLinksDomain: String
    let logAsync: Bool
    let logFormat: String
    let onesignalAppID: String
    let revenuecatAPIKey: String
    let serverSchemaVersion: String
}

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    let log = Logger.self
    let config: AppConfig
    let keychain: Keychain<CryptoPublicKey, CryptoPrivateKey>
    let database: Database = RealmDatabase()
    let purchasesController: PurchasesController
    let api: API
    let authenticationService: AuthenticationService

    var privacyPolicyLoader: WebDocumentLoader? = nil
    var window: UIWindow?   // DO NOT DELETE - required for AppDelegate (https://developer.apple.com/library/archive/referencelibrary/GettingStarted/DevelopiOSAppsSwift/BuildABasicUI.html) - causes black window if not present
    var context: AppContext?
    var dataService: DataService?
    var userNotificationProvider: UserNotificationProvider?

    override init() {
        let infoPlist = Bundle.main.infoDictionary!
        let infoPlistAppConfig = infoPlist["AppConfig"] as! Dictionary<String, Any>

        config = AppConfig(
            apiBaseURL: infoPlistAppConfig["API_BASE_URL"] as! String,
            appVersion: "\(infoPlist["CFBundleShortVersionString"] as! String).\(infoPlist["CFBundleVersion"] as! String)",
            appStoreID: infoPlistAppConfig["APP_STORE_ID"] as! String,
            appStoreURL: infoPlistAppConfig["APP_STORE_URL"] as! String,
            awsAssetsBucket: infoPlistAppConfig["AWS_ASSETS_BUCKET"] as! String,
            awsAssetsBucketRegion: infoPlistAppConfig["AWS_ASSETS_BUCKET_REGION"] as! String,
            domain: infoPlistAppConfig["DOMAIN"] as! String,
            federationProvider: infoPlistAppConfig["FEDERATION_PROVIDER"] as! String,
            firebaseDynamicLinksDomain: infoPlistAppConfig["FIREBASE_DYNAMICLINKS_DOMAIN"] as! String,
            logAsync: Bool(infoPlistAppConfig["LOG_ASYNC"] as! String)!,
            logFormat: "$C[$L]$c $Dyyyy-MM-dd HH:mm:ss.SSS$d    $n: $F:$l: $M",
            onesignalAppID: infoPlistAppConfig["ONESIGNAL_APP_ID"] as! String,
            revenuecatAPIKey: infoPlistAppConfig["REVENUECAT_APIKEY"] as! String,
            serverSchemaVersion: infoPlistAppConfig["SERVER_SCHEMA_VERSION"] as! String
        )

        #if DEBUG
        keychain = Keychain<CryptoPublicKey, CryptoPrivateKey>(environment: .debug)
        #else
        keychain = Keychain<CryptoPublicKey, CryptoPrivateKey>(environment: .prod)
        #endif
        api = API(host: config.apiBaseURL)
        purchasesController = PurchasesController(apiKey: config.revenuecatAPIKey)
        authenticationService = AuthenticationService(emailAuthenticationFallbackURL: URL(string: config.appStoreURL)!)

        super.init()
    }

    func application(_ application: UIApplication, willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        return true
    }

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // initialise
        setup()
        dataService = AWSAdapter()
        userNotificationProvider = UserNotificationProvider(appID: config.onesignalAppID, didFinishLaunchingWithOptions: launchOptions)
        log.debug(config)
        presentNextRootViewController()

        if #available(iOS 13.0, *) {
            registerBackgroundTasks()
        }

        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
        if let (importsInProgress, containsManualImports) = context?.assetManager.imports, importsInProgress {
            let message: String
            if containsManualImports {
                message = "Manual imports are in progress. Please keep TripUp open to finish syncing."
            } else {
                if #available(iOS 13.0, *) {
                    message = "Library will continue backing up when your device is idle and connected to power."
                } else {
                    message = "Library is still backing up. Please keep TripUp open app until backup is complete."
                }
            }
            userNotificationProvider?.local(message: message)
        }

        if #available(iOS 13.0, *), UserDefaults.standard.bool(forKey: UserDefaultsKey.AutoBackup.rawValue) {
            scheduleBackgroundTasks()
        }
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
        context?.networkMonitor?.refresh()  // should trigger context update
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        context?.generateStatusNotification()
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
        // Saves changes in the application's managed object context before the application terminates.
    }

    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        if let awsAdapter = dataService as? AWSAdapter {
            awsAdapter.application(application, handleEventsForBackgroundURLSession: identifier, completionHandler: completionHandler)
        }
    }
}
