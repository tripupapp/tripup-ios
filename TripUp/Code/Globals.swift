//
//  Closure.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 12/10/2017.
//  Copyright © 2017 Vinoth Ramiah. All rights reserved.
//

import Foundation

typealias Closure = () -> Void
typealias ClosureBool = (Bool) -> Void

protocol ArrayOrSet: Collection {
    init<S: Sequence>(_ elements: S) where S.Element == Element
}

struct IndexPathItems {
    let deletedItems: [IndexPath]
    let insertedItems: [IndexPath]
    let movedItems: [[IndexPath]]
}

struct Globals {
    struct Documents {
        static let privacyPolicy = WebDocument(bundleResource: (resource: "script-privacypolicy", extension: "txt"), verificationString: "Privacy Policy of", renderedFilename: "privacypolicy.html")
    }

    struct Directories {
        static let SandboxRoot = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        static let Documents = try! FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        static let ApplicationSupport = try! FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        static let Caches = try! FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        /**
         tmp/

         Always on boot volume (on iOS there is only 1 volume, as of iOS 14.3)

         # NOTE: Reason for not using .itemReplacementDirectory

         FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: destinationURL, create: true) creates a temporary directory suitable for (on same volume as) destinationURL <https://nshipster.com/temporary-files/>.

         ## Limitations
         <https://openradar.appspot.com/50553219>

         User is expected to remove these directories when done. Directories that aren't deleted aren't reused (even if they're empty) and the system seems to have an upper limit of 1000 generated directories, according to the bug report. Furthermore, directory names aren't random but based on app name e.g. "A Document Being Saved By TripUp #NUMBER". Decided that possibility of collisions was too high (multiple processes generating temp directories simulatenously) and didn't want hassle of having to track directories (for example, when a download fails, have to remember to delete directory).

         ## Simulator differences
         - Device: The temporary folder will be created inside tmp/
         - Simulator: The temporary folder will be created outside tmp/, usually at same folder as destinationURL

         <https://gist.github.com/steipete/d7a1506cdb1300cba0a3ae1b11450ab5>
         */
        static let tmp = FileManager.default.temporaryDirectory

        static let tripupPrefix = "tripup/"
        static let legal = ApplicationSupport.appendingPathComponent(tripupPrefix + "legal", isDirectory: true)
        static let assetsLow = ApplicationSupport.appendingPathComponent(tripupPrefix + "assets-low", isDirectory: true)
        static let assetsOriginal = Caches.appendingPathComponent(tripupPrefix + "assets-original", isDirectory: true)
    }
}

enum UserDefaultsKey: String {
    case LoginInProgress
    case PrimaryUser
    case AppVersionNumber
    case GestureTutorialPlayed
    case ReceivedAssetTutorial
    case PasswordBackupOption
    case AutoBackup
    case ServerSchemaVersion
    case DebugLogs
}
