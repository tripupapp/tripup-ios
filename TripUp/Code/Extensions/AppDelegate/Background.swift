//
//  Background.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 20/02/2021.
//  Copyright © 2021 Vinoth Ramiah. All rights reserved.
//

import Foundation
import BackgroundTasks

@available(iOS 13.0, *)
extension AppDelegate {
    func registerBackgroundTasks() {
        // declared under the "Permitted background task scheduler identifiers" item in Info.plist
        let backgroundProcessingTaskSchedulerIdentifier = "app.tripup.importAssets"

        BGTaskScheduler.shared.register(forTaskWithIdentifier: backgroundProcessingTaskSchedulerIdentifier, using: nil) { (task) in
            self.log.debug("Background Task Start")
            task.expirationHandler = {
                self.context?.assetManager.cancelBackgroundImports()
                self.log.debug("Background Task End - expired")
                task.setTaskCompleted(success: false)
            }
            self.context?.assetManager.startBackgroundImports { (success) in
                self.log.debug("Background Task End - success: \(success)")
                task.setTaskCompleted(success: success)
            }
            self.scheduleBackgroundTasks()
         }
    }

    func scheduleBackgroundTasks() {
        let assetsImportTaskRequest = BGProcessingTaskRequest(identifier: "app.tripup.importAssets")
        assetsImportTaskRequest.requiresExternalPower = true
        assetsImportTaskRequest.requiresNetworkConnectivity = true
        assetsImportTaskRequest.earliestBeginDate = Date(timeIntervalSinceNow: 60)
        do {
            try BGTaskScheduler.shared.submit(assetsImportTaskRequest)
        } catch {
            print("Unable to submit task: \(error.localizedDescription)")
        }
    }
}
