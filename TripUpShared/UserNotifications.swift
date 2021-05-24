//
//  UserNotifications.swift
//  TripUpShared
//
//  Created by Vinoth Ramiah on 14/02/2021.
//  Copyright © 2021 Vinoth Ramiah. All rights reserved.
//

import Foundation

public enum UserNotificationType: String {
    case invitedToGroup
    case userJoinedGroup
    case userLeftGroup
    case assetsChangedForGroup
    case assetsAddedToGroupByUser
    
    public var contentStrings: (title: String, message: String)? {
        switch self {
        case .invitedToGroup:
            return ("New Group 🎉", "You've been added to a new group album! Open TripUp to start sharing photos")
        case .userJoinedGroup:
            return ("New User 👋", "Someone has joined one of your group albums! Open TripUp to share some photos with them")
        case .assetsAddedToGroupByUser:
            return ("New Photos 📸", "Someone has shared photos in a group album! Open TripUp to see them")
        default:
            return nil
        }
    }
}

public struct UserNotification {
    public let type: UserNotificationType
    public let groupID: UUID?
    
    public init(type: UserNotificationType, groupID: UUID?) {
        self.type = type
        self.groupID = groupID
    }
}
