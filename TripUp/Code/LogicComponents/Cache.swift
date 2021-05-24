//
//  Cache.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 19/03/2021.
//  Copyright © 2021 Vinoth Ramiah. All rights reserved.
//

import Foundation
import UIKit.UIApplication

class CacheDelegate<KeyType> {
    func isDiscardable<T>(keysToTest: T, callbackWithDiscardableKeys: @escaping (AnyCollection<KeyType>) -> Void) where T: Collection, T.Element == KeyType {}
}

class Cache<KeyType, ObjectType> where KeyType: Hashable, ObjectType: AnyObject {
    enum CacheError: Error {
        case objectExistsForKey(KeyType, ObjectType)
    }

    var delegate: CacheDelegate<KeyType>?

    private let dispatchQueue: DispatchQueue
    private var dict = [KeyType: ObjectType]()
    private var memoryWarningObserverToken: NSObjectProtocol?

    init() {
        dispatchQueue = DispatchQueue(label: String(describing: Cache.self), attributes: .concurrent, target: .global())
        memoryWarningObserverToken = NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil) { [unowned self] (_) in
            self.dispatchQueue.async { [weak self] in
                guard let self = self else {
                    return
                }
                let keys = self.dict.keys
                self.removeObjects(forKeys: keys)
            }
        }
    }

    deinit {
        if let memoryWarningObserverToken = memoryWarningObserverToken {
            NotificationCenter.default.removeObserver(memoryWarningObserverToken, name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        }
    }

    func object(forKey key: KeyType) -> ObjectType? {
        dispatchQueue.sync {
            return dict[key]
        }
    }

    func setObject(_ object: ObjectType, forKey key: KeyType) throws {
        try dispatchQueue.sync(flags: .barrier) {
            if let existingObject = dict[key] {
                throw CacheError.objectExistsForKey(key, existingObject)
            } else {
                dict[key] = object
            }
        }
    }

    func removeObject(forKey key: KeyType) {
        removeObjects(forKeys: [key])
    }

    func removeObjects<T>(forKeys keys: T) where T: Collection, T.Element == KeyType {
        if let delegate = delegate {
            delegate.isDiscardable(keysToTest: keys) { [weak self] (discardableKeys) in
                self?.removeAsync(keys: discardableKeys)
            }
        } else {
            removeAsync(keys: keys)
        }
    }

    private func removeAsync<T>(keys: T) where T: Collection, T.Element == KeyType {
        dispatchQueue.async(flags: .barrier) { [weak self] in
            for key in keys {
                self?.dict[key] = nil
            }
        }
    }
}
