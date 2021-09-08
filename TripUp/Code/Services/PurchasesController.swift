//
//  PurchasesController.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 27/03/2020.
//  Copyright © 2020 Vinoth Ramiah. All rights reserved.
//

import Foundation

import Purchases

struct StorageTier {
    static let free: StorageTier = StorageTier(size: 2147483648)    // 2 GB

    let size: UInt64

    init(size: UInt64) {
        self.size = size
    }

    init?(entitledIdentifier: String) {
        if entitledIdentifier == "unlimited" {
            self.size = UInt64.max
        } else {
            guard let number = UInt64(entitledIdentifier) else {
                assertionFailure(entitledIdentifier)
                return nil
            }
            self.size = number * 1024 * 1024 * 1024 // number to GB
        }
    }

    init?(packageIdentifier: String) {
        guard let index = packageIdentifier.firstIndex(of: "_") else {
            assertionFailure(packageIdentifier)
            return nil
        }
        guard let number = UInt64(packageIdentifier.prefix(upTo: index)) else {
            assertionFailure("\(packageIdentifier), \(index)")
            return nil
        }
        self.size = number * 1024 * 1024 * 1024 // number to GB
    }
}

extension StorageTier: Equatable {}

extension StorageTier: CustomStringConvertible {
    var description: String {
        if size == UInt64.max {
            return "♾️"
        }
        guard let int64 = Int64(exactly: size) else { fatalError("\(size)") }
        return ByteCountFormatter.string(fromByteCount: int64, countStyle: .binary)
    }
}

protocol PurchasesObserver: AnyObject {
    func updated(storageTier: StorageTier)
}

class PurchasesController {
    struct Parcel {
        var price: String {
            package.localizedPriceString
        }
        var subscriptionPeriod: String {
            guard let subscription = package.product.subscriptionPeriod else { return "One-Time Purchase" }
            switch (subscription.unit, subscription.numberOfUnits) {
            case (.month, 1):
                return "Month"
            case (.year, 1):
                return "Year"
            default:
                fatalError("unit: \(subscription.unit), numberOfUnits: \(subscription.numberOfUnits)")
            }
        }
        let storageTier: StorageTier
        let package: Purchases.Package
    }

    private(set) var signedIn = false
    private let log = Logger.self
    private let purchasesObserverDelegate = PurchasesControllerObserverDelegate()

    init(apiKey: String) {
        let userDefaults = UserDefaults(suiteName: "app.tripup.revenuecat")!    // needed as we clear standard user defaults at various times. https://support.revenuecat.com/hc/en-us/articles/360053838273-My-app-crashes-with-
        Purchases.configure(withAPIKey: apiKey, appUserID: nil, observerMode: false, userDefaults: userDefaults)
    }

    func signIn(userID: String) {
        Purchases.shared.identify(userID, nil)
        Purchases.shared.delegate = purchasesObserverDelegate
        signedIn = true
    }

    func signOut() {
        Purchases.shared.reset(nil)
        Purchases.shared.delegate = nil
        signedIn = false
    }
}

extension PurchasesController {
    func entitled(callback: @escaping (StorageTier) -> Void) {
        Purchases.shared.purchaserInfo { (purchaserInfo, error) in
            guard let purchaserInfo = purchaserInfo else {
                self.log.error(error?.localizedDescription ?? "error retrieving subscription status")
                callback(.free)
                return
            }
            guard let entitled = purchaserInfo.entitlements.active.first?.value else {
                callback(.free)
                return
            }
            guard let tier = StorageTier(entitledIdentifier: entitled.identifier) else {
                assertionFailure(entitled.identifier)
                callback(.free)
                return
            }
            callback(tier)
        }
    }

    func offers(callback: @escaping ([Parcel]?) -> Void) {
        Purchases.shared.offerings { (offerings, error) in
            if let currentOffers = offerings?.current {
                let currentParcels: [Parcel] = currentOffers.availablePackages.compactMap {
                    guard let tier = StorageTier(packageIdentifier: $0.identifier) else {
                        return nil
                    }
                    return Parcel(storageTier: tier, package: $0)
                }
                callback(currentParcels.sorted(by: { $0.storageTier.size < $1.storageTier.size }))
            } else {
                self.log.error(error?.localizedDescription ?? "error retrieving offerings")
                callback(nil)
            }
        }
    }

    func purhase(_ parcel: Parcel, callback: @escaping ClosureBool) {
        Purchases.shared.purchasePackage(parcel.package) { (transaction, purchaserInfo, error, userCancelled) in
            if purchaserInfo?.entitlements.active.first != nil {
                callback(true)
            } else {
                if userCancelled {
                    self.log.warning("user cancelled purchase of: \(String(describing: parcel.storageTier)), for: \(parcel.price)")
                } else {
                    self.log.error(error?.localizedDescription ?? "something went wrong with purchasing: \(String(describing: parcel.storageTier)), for: \(parcel.price)")
                }
                callback(false)
            }
        }
    }
}

extension PurchasesController {
    func addObserver(_ observer: PurchasesObserver) {
        purchasesObserverDelegate.addObserver(observer)
    }

    func removeObserver(_ observer: PurchasesObserver) {
        purchasesObserverDelegate.removeObserver(observer)
    }
}

class PurchasesControllerObserverDelegate: NSObject {
    private struct Observation {
        weak var observer: PurchasesObserver?
    }

    private var observations = [ObjectIdentifier: Observation]()

    func addObserver(_ observer: PurchasesObserver) {
        assert(Thread.isMainThread)
        let id = ObjectIdentifier(observer)
        observations[id] = Observation(observer: observer)
    }

    func removeObserver(_ observer: PurchasesObserver) {
        assert(Thread.isMainThread)
        let id = ObjectIdentifier(observer)
        observations.removeValue(forKey: id)
    }
}

extension PurchasesControllerObserverDelegate: PurchasesDelegate {
    func purchases(_ purchases: Purchases, didReceiveUpdated purchaserInfo: Purchases.PurchaserInfo) {
        assert(Thread.isMainThread)
        var storageTier: StorageTier?
        if let entitled = purchaserInfo.entitlements.active.first?.value {
            storageTier = StorageTier(entitledIdentifier: entitled.identifier)
        }

        for (id, observation) in observations {
            guard let observer = observation.observer else {
                observations.removeValue(forKey: id)
                continue
            }
            observer.updated(storageTier: storageTier ?? .free)
        }
    }
}
