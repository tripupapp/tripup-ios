//
//  Logger.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 15/08/2019.
//  Copyright © 2019 Vinoth Ramiah. All rights reserved.
//

import Foundation
import SwiftyBeaver

struct Logger {
    private static let log = SwiftyBeaver.self

    static func configure(with config: AppConfig) {
        #if DEBUG
        if UserDefaults.standard.object(forKey: UserDefaultsKey.DebugLogs.rawValue) == nil {
            UserDefaults.standard.set(true, forKey: UserDefaultsKey.DebugLogs.rawValue)
        }
        #endif
        let debugLogs = UserDefaults.standard.bool(forKey: UserDefaultsKey.DebugLogs.rawValue)

        #if DEBUG
        let console = ConsoleDestination()
        console.asynchronously = config.logAsync
        console.format = config.logFormat
        console.minLevel = debugLogs ? .debug : .info
        log.addDestination(console)
        #endif

        let file = FileDestination()
        file.asynchronously = config.logAsync
        file.format = config.logFormat
        file.minLevel = debugLogs ? .debug : .info
        log.addDestination(file)
    }

    static func verbose(_ message: Any, _ file: String = #file, _ function: String = #function, line: Int = #line) {
        log.verbose(message, file, function, line: line)
    }

    static func debug(_ message: Any, _ file: String = #file, _ function: String = #function, line: Int = #line) {
        log.debug(message, file, function, line: line)
    }

    static func info(_ message: Any, _ file: String = #file, _ function: String = #function, line: Int = #line) {
        log.info(message, file, function, line: line)
    }

    static func warning(_ message: Any, _ file: String = #file, _ function: String = #function, line: Int = #line) {
        log.warning(message, file, function, line: line)
    }

    static func error(_ message: Any, _ file: String = #file, _ function: String = #function, line: Int = #line) {
        log.error(message, file, function, line: line)
    }

    static func setDebugLevel(on: Bool) {
        UserDefaults.standard.set(on, forKey: UserDefaultsKey.DebugLogs.rawValue)
        let level: SwiftyBeaver.Level = on ? .debug : .info
        log.destinations.forEach{ $0.minLevel = level }
    }

    static func logFileURL() -> URL? {
        if let fileDestination = log.destinations.first(where: { $0 is FileDestination }) as? FileDestination {
            return fileDestination.logFileURL
        }
        return nil
    }

    static func deleteLogFile() {
        if let fileDestination = log.destinations.first(where: { $0 is FileDestination }) as? FileDestination {
            guard fileDestination.deleteLogFile() else {
                fatalError()
            }
        } else {
            assertionFailure()
        }
    }
}
