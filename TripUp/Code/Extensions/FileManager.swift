//
//  FileManager.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 21/06/2021.
//  Copyright © 2021 Vinoth Ramiah. All rights reserved.
//

import Foundation

extension FileManager {
    func createUniqueTempDir() -> URL? {
        let tempDir = Globals.Directories.tmp.appendingPathComponent("\(ProcessInfo().globallyUniqueString)", isDirectory: true)
        do {
            try createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
        } catch {
            Logger.self.error("could not create unique temp file - error: \(String(describing: error))")
            return nil
        }
        return tempDir
    }

    func createUniqueTempFile(filename: String, fileExtension: String? = nil) -> URL? {
        let tempDir = createUniqueTempDir()
        return tempDir?.appendingPathComponent(filename, isDirectory: false).appendingPathExtension(fileExtension ?? "")
    }
}
