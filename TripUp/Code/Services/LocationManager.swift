//
//  LocationManager.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 05/07/2019.
//  Copyright © 2019 Vinoth Ramiah. All rights reserved.
//

import Foundation
import CoreLocation

class LocationManager: NSObject {
    private let locationManager = CLLocationManager()
    private var status = CLLocationManager.authorizationStatus()
    private var running = false

    var currentLocation: TULocation? {
        guard running, let location = locationManager.location else { return nil }
        return TULocation(location)
    }

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        switch status {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .restricted, .denied:
            break
        case .authorizedWhenInUse, .authorizedAlways:
            start()
        @unknown default:
            fatalError()
        }
    }

    deinit {
        stop()
    }

    func start() {
        if CLLocationManager.locationServicesEnabled() {
            locationManager.startUpdatingLocation()
            running = true
        }
    }

    func stop() {
        locationManager.stopUpdatingLocation()
        running = false
    }
}

extension LocationManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        switch status {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .restricted, .denied:
            stop()
        case .authorizedWhenInUse, .authorizedAlways:
            start()
        @unknown default:
            fatalError()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {

    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {

    }
}
