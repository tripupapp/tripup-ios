//
//  UserNotifications.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 12/02/2021.
//  Copyright © 2021 Vinoth Ramiah. All rights reserved.
//

import Foundation
import UIKit.UIApplication

import OneSignal

import TripUpShared

protocol UserNotificationReceiver: AnyObject {
    func receive(_ notification: UserNotification, completion: @escaping ClosureBool)
}

class UserNotificationProvider {
    weak var receiver: UserNotificationReceiver?
    
    init(appID: String, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) {
        OneSignal.setLogLevel(.LL_WARN, visualLevel: .LL_NONE)
        OneSignal.initWithLaunchOptions(launchOptions)
        OneSignal.setAppId(appID)
        
        OneSignal.setNotificationWillShowInForegroundHandler({ (OSNotification, completion) in
            // TODO: make decision based on notification type and window currently on display
            completion(nil) // silence notifications
        })
    }
    
    func signIn(userID: UUID) {
        OneSignal.setExternalUserId(userID.string, withSuccess: nil) { (error) in
            fatalError(String(describing: error))
        }
    }
    
    func signOut() {
        OneSignal.removeExternalUserId(nil) { (error) in
            fatalError(String(describing: error))
        }
    }
}

extension UserNotificationProvider {
    var notificationPermisssionUndetermined: Bool {
        if let state = OneSignal.getDeviceState() {
            return state.notificationPermissionStatus == .notDetermined
        }
        return true
    }

    func promptForPermission() {
        OneSignal.promptForPushNotifications(userResponse: { (_) in

        })
    }
    
    func local(message: String) {
        if let playerID = OneSignal.getDeviceState()?.userId {
            OneSignal.postNotification([
                "include_player_ids": [playerID],
                "contents": ["en": message]
            ])
        }
    }
}
