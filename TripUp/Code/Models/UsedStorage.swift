//
//  UsedStorage.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 25/06/2021.
//  Copyright © 2021 Vinoth Ramiah. All rights reserved.
//

import Foundation

struct UsedStorage {
    let photos: (count: Int, totalSize: Int64)
    let videos: (count: Int, totalSize: Int64)

    var totalSize: Int64 {
        return photos.totalSize + videos.totalSize
    }
}
