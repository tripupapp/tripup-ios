//
//  TULocationExtensions.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 04/07/2019.
//  Copyright © 2019 Vinoth Ramiah. All rights reserved.
//

import Foundation
import CoreLocation

extension TULocation {
    init(latitude: Double, longitude: Double, altitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
    }

    init(_ location: CLLocation) {
        self.latitude = location.coordinate.latitude
        self.longitude = location.coordinate.longitude
        self.altitude = location.altitude
    }

    init?(_ location: CLLocation?) {
        guard let location = location else { return nil }
        self.init(location)
    }

    init?(_ serializedString: String) {
        guard let serializedData = Data(base64Encoded: serializedString) else { return nil }
        guard let location = try? TULocation(serializedData: serializedData) else { return nil }
        self = location
    }

    var coreLocation: CLLocation {
        return CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            altitude: altitude,
            horizontalAccuracy: 0,
            verticalAccuracy: 0,
            course: -1,
            speed: -1,
            timestamp: Date())
    }

    var serializedString: String {
        return try! self.serializedData().base64EncodedString()
    }
}
