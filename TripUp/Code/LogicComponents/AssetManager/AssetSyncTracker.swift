//
//  AssetSyncTracker.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 17/08/2020.
//  Copyright © 2020 Vinoth Ramiah. All rights reserved.
//

import Foundation

protocol AssetSyncObserver: class {
    func update(completedUpdates: Int, totalUpdates: Int)
}

extension AssetManager {
    class AssetSyncTracker {
        private struct ObserverWrapper {
            weak var observer: AssetSyncObserver?
        }

        private var unsyncedAssets = Set<UUID>()
        private var syncedAssets = Set<UUID>()

        private var completed: Int {
            return syncedAssets.count
        }
        private var total: Int {
            return syncedAssets.count + unsyncedAssets.count
        }

        private let dispatchQueue = DispatchQueue(label: String(describing: AssetSyncTracker.self), qos: .default, target: DispatchQueue.global())
        private var observers = [ObjectIdentifier: ObserverWrapper]()

        func startTracking<T: Collection>(_ assetIDs: T) where T.Element == UUID {
            assert(assetIDs.isNotEmpty)
            dispatchQueue.async { [weak self] in
                guard let self = self else { return }
                self.unsyncedAssets = self.unsyncedAssets.union(assetIDs)
                self.notifyObservers(completed: self.completed, total: self.total)
            }
        }

        func completeTracking<T: Collection>(_ assetIDs: T) where T.Element == UUID {
            assert(assetIDs.isNotEmpty)
            dispatchQueue.async { [weak self] in
                guard let self = self else { return }
                let unsyncedAssets = self.unsyncedAssets.subtracting(assetIDs)
                self.syncedAssets = self.syncedAssets.union(self.unsyncedAssets.subtracting(unsyncedAssets))
                self.unsyncedAssets = unsyncedAssets
                self.notifyObservers(completed: self.completed, total: self.total)
                if self.completed == self.total {
                    self.unsyncedAssets.removeAll()
                    self.syncedAssets.removeAll()
                }
            }
        }

        func removeTracking<T: Collection>(_ assetIDs: T) where T.Element == UUID {
            assert(assetIDs.isNotEmpty)
            dispatchQueue.async { [weak self] in
                guard let self = self else { return }
                self.unsyncedAssets.subtract(assetIDs)
                self.notifyObservers(completed: self.completed, total: self.total)
                if self.completed == self.total {
                    self.unsyncedAssets.removeAll()
                    self.syncedAssets.removeAll()
                }
            }
        }

        private func notifyObservers(completed: Int, total: Int) {
            DispatchQueue.main.async {
                for (id, observerWrapper) in self.observers {
                    guard let observer = observerWrapper.observer else {
                        self.observers.removeValue(forKey: id)
                        continue
                    }
                    observer.update(completedUpdates: completed, totalUpdates: total)
                }
            }
        }

        func addObserver(_ observer: AssetSyncObserver) {
            assert(Thread.isMainThread)
            let id = ObjectIdentifier(observer)
            observers[id] = ObserverWrapper(observer: observer)
            dispatchQueue.async { [weak self] in
                guard let self = self else { return }
                let completedUpdates = self.completed
                let totalUpdates = self.total
                DispatchQueue.main.async {
                    observer.update(completedUpdates: completedUpdates, totalUpdates: totalUpdates)
                }
            }
        }

        func removeObserver(_ observer: AssetSyncObserver) {
            assert(Thread.isMainThread)
            let id = ObjectIdentifier(observer)
            observers.removeValue(forKey: id)
        }
    }
}
