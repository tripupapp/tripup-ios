//
//  NotificationService.swift
//  OneSignalNotificationServiceExtension
//
//  Created by Vinoth Ramiah on 11/02/2021.
//  Copyright © 2021 Vinoth Ramiah. All rights reserved.
//

import UserNotifications

import OneSignal

import TripUpShared

class NotificationService: UNNotificationServiceExtension {
    var receivedRequest: UNNotificationRequest!
    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.receivedRequest = request
        self.contentHandler = contentHandler
        self.bestAttemptContent = request.content.mutableCopy() as? UNMutableNotificationContent

        guard let bestAttemptContent = bestAttemptContent else {
            return
        }

        // Modify the notification content here...
        
        // userInfo["custom"]["a"] is equivalent to OneSignals additionalData dictionary
        if let custom = request.content.userInfo["custom"] as? [AnyHashable: Any], let a = custom["a"] as? [AnyHashable: Any], let notificationTypeString = a["signal"] as? String, let notificationType = UserNotificationType(rawValue: notificationTypeString) {
            if let contentStrings = notificationType.contentStrings {
                bestAttemptContent.title = contentStrings.title
                bestAttemptContent.body = contentStrings.message

                if let _ = a["groupid"] as? String {
                    // TODO: resolve groupid to a group name, to use in formatted title/body
                }
            }
        }
        OneSignal.didReceiveNotificationExtensionRequest(receivedRequest, with: bestAttemptContent, withContentHandler: contentHandler)
    }
    
    override func serviceExtensionTimeWillExpire() {
        // Called just before the extension will be terminated by the system.
        // Use this as an opportunity to deliver your "best attempt" at modified content, otherwise the original push payload will be used.
        if let contentHandler = contentHandler, let bestAttemptContent =  bestAttemptContent {
            OneSignal.serviceExtensionTimeWillExpireRequest(receivedRequest, with: bestAttemptContent)
            contentHandler(bestAttemptContent)
        }
    }

}
