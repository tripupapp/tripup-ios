//
//  FileSystem.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 24/06/2021.
//  Copyright © 2021 Vinoth Ramiah. All rights reserved.
//

import Foundation

class FileSystem {
    static let `default` = FileSystem()
}

extension FileSystem {
    func processFile(atURL url: URL, chunkSize: Int, block: (Data) -> Void) {
        assert(!Thread.isMainThread)
        let fileHandle: FileHandle
        do {
            try fileHandle = FileHandle(forReadingFrom: url)
        } catch {
            fatalError(String(describing: error))
        }
        fileHandle.seek(toFileOffset: 0)
        var hasData: Bool = true
        repeat {
            autoreleasepool {
                let data = fileHandle.readData(ofLength: chunkSize)
                hasData = data.count > 0
                if hasData {
                    block(data)
                }
            }
        } while hasData
    }

    func write(streamData: () -> Data?, toURL url: URL) {
        assert(!Thread.isMainThread)
        FileManager.default.createFile(atPath: url.path, contents: nil, attributes: nil)
        let fileHandle: FileHandle
        do {
            try fileHandle = FileHandle(forWritingTo: url)
        } catch {
            fatalError(String(describing: error))
        }
        fileHandle.seek(toFileOffset: 0)
        var hasData: Bool = true
        repeat {
            autoreleasepool {
                let data = streamData()
                if let data = data {
                    hasData = !data.isEmpty
                    if hasData {
                        fileHandle.write(data)
                    }
                } else {
                    hasData = false
                }
            }
        } while hasData
    }
}
