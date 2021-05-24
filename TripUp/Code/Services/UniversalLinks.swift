//
//  UniversalLinks.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 01/06/2020.
//  Copyright © 2020 Vinoth Ramiah. All rights reserved.
//

import Foundation

import FirebaseDynamicLinks

class UniversalLinksService {
    enum UniversalLink {
        case user(UUID)
    }

    static let shared = UniversalLinksService()
    var domain: String?
    var dynamicLinksDomain: String?
    var appStoreID: String?

    private let log = Logger.self

    private init() {}

    func generate(forUser user: User, callback: @escaping (URL?) -> Void) {
        guard let domain = domain, let userURL = URL(string: "\(domain)/users/\(user.uuid.string)") else {
            DispatchQueue.main.async {
                callback(nil)
            }
            return
        }
        generateLink(withURL: userURL, callback: callback)
    }

    func handle(link: URL, callback: @escaping (UniversalLink?) -> Void) -> Bool {
        let handled = DynamicLinks.dynamicLinks().handleUniversalLink(link) { (dynamicLink, error) in
            if let error = error {
                self.log.error("link: \(String(describing: link)), error: \(String(describing: error))")
            }
            var item: UniversalLink?
            switch dynamicLink?.url?.pathComponents {
            case .some(let components) where components[1] == "users":
                if let userID = UUID(uuidString: components[2]) {
                    item = .user(userID)
                } else {
                    self.log.error("invalid uuid: \(components[2])")
                }
            default:
                self.log.error("unrecognised universal link - dynamicLink: \(String(describing: dynamicLink))")
            }
            DispatchQueue.main.async {
                callback(item)
            }
        }
        return handled
    }

    private func generateLink(withURL url: URL, callback: @escaping (URL?) -> Void) {
        guard let dynamicLinksDomainURIPrefix = dynamicLinksDomain, let linkBuilder = DynamicLinkComponents(link: url, domainURIPrefix: dynamicLinksDomainURIPrefix) else {
            DispatchQueue.main.async {
                callback(nil)
            }
            return
        }
        let iosParams = DynamicLinkIOSParameters(bundleID: Bundle.main.bundleIdentifier!)
        iosParams.appStoreID = appStoreID
        linkBuilder.iOSParameters = iosParams
        linkBuilder.shorten(completion: { (url, warnings, error) in
            if let error = error {
                self.log.error("url: \(String(describing: url)), error: \(String(describing: error))")
            }
            if let warnings = warnings {
                self.log.warning("url: \(String(describing: url)), error: \(String(describing: warnings))")
            }
            callback(url)
        })
    }
}
