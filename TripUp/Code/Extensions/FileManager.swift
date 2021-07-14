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

    func uniqueTempFile(filename: String, fileExtension: String? = nil) -> URL? {
        let tempDir = createUniqueTempDir()
        return tempDir?.appendingPathComponent(filename, isDirectory: false).appendingPathExtension(fileExtension ?? "")
    }

    func moveItem(at sourceURL: URL, to destinationURL: URL, createIntermediateDirectories: Bool, overwrite: Bool) throws {
        do {
            try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
        } catch let error as NSError where error.code == NSFileNoSuchFileError && createIntermediateDirectories {
            try FileManager.default.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
            try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
        } catch let error as NSError where error.code == NSFileWriteFileExistsError && overwrite {
            try FileManager.default.removeItem(at: destinationURL)
            try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
        }
    }

    func removeItem(at URL: URL, idempotent: Bool) throws {
        do {
            try FileManager.default.removeItem(at: URL)
        } catch CocoaError.fileNoSuchFile where idempotent {}
    }
}
