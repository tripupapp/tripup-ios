//
//  NetworkMonitor.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 19/09/2018.
//  Copyright © 2018 Vinoth Ramiah. All rights reserved.
//

import Foundation
import Connectivity

protocol NetworkObserver: AnyObject {
    func networkChanged(toState state: NetworkMonitor.State)
}

protocol NetworkObserverRegister {
    func addObserver(_ observer: NetworkObserver)
    func removeObserver(_ observer: NetworkObserver)
}

protocol NetworkStatusReporter: AnyObject {
    var isOnline: Bool { get }
    var isOnlineViaWiFi: Bool { get }
}

protocol NetworkMonitorController: AnyObject {
    func refresh()
}

class NetworkMonitor {
    enum State {
        case online(mobile: Bool?)
        case notOnline
    }

    private struct NetworkObserverWrapper {
        weak var observer: NetworkObserver?
    }

    private let generalNetworkConnectivity: Connectivity = Connectivity()
    private let tripupServerConnectivity: Connectivity = Connectivity()
    private let authenticatedUser: AuthenticatedUser
    private var networkObservers = [ObjectIdentifier: NetworkObserverWrapper]()
    private var autoBackupObserverToken: NSObjectProtocol?
    private var started: Bool = false

    init?(host hostCandidate: String, authenticatedUser: AuthenticatedUser) {
        self.authenticatedUser = authenticatedUser
        self.autoBackupObserverToken = NotificationCenter.default.addObserver(forName: .AutoBackupChanged, object: nil, queue: nil) { [weak self] _ in
            if let self = self, !self.tripupServerConnectivity.isConnected {
                self.generalNetworkConnectivity.checkConnectivity()
            }
        }

        guard let connectivityTestPoint = URL(string: hostCandidate + "/ping") else {
            return nil
        }

        #if DEBUG
            Connectivity.isHTTPSOnly = false
        #endif

        generalNetworkConnectivity.framework = .network     // use newer Network framework (ios 12+) if available - provides greater accuracy
        generalNetworkConnectivity.checkWhenApplicationDidBecomeActive = true
        generalNetworkConnectivity.whenConnected = { [weak self] connectivity in
            self?.checkTripUpServerConnectivity()

        }
        generalNetworkConnectivity.whenDisconnected = { [weak self] connectivity in
            self?.observers(notify: connectivity.status)
        }

        tripupServerConnectivity.framework = .network       // use newer Network framework (ios 12+) if available - provides greater accuracy
        tripupServerConnectivity.connectivityURLs = [connectivityTestPoint]
        precondition(tripupServerConnectivity.connectivityURLs.isNotEmpty)
        tripupServerConnectivity.expectedResponseString = "TripUp"
        tripupServerConnectivity.validationMode = .equalsExpectedResponseString
    }

    deinit {
        if let autoBackupObserverToken = autoBackupObserverToken {
            NotificationCenter.default.removeObserver(autoBackupObserverToken, name: .AutoBackupChanged, object: nil)
        }
    }

    private func checkTripUpServerConnectivity() {
        authenticatedUser.token({ [weak self] (token) in
            guard let token = token, token.notExpired else {
                self?.observers(notify: .notConnected)
                return
            }
            self?.tripupServerConnectivity.bearerToken = token.value
            self?.tripupServerConnectivity.checkConnectivity(completion: { [weak self] (connectivity) in
                self?.observers(notify: connectivity.status)
            })
        })
    }

    private func observers(notify status: ConnectivityStatus) {
        guard status != .determining else {
            return
        }
        DispatchQueue.main.async {
            for (id, observerWrapper) in self.networkObservers {
                guard let observer = observerWrapper.observer else {
                    self.networkObservers.removeValue(forKey: id)
                    continue
                }
                switch status {
                case .connectedViaWiFi:
                    observer.networkChanged(toState: .online(mobile: false))
                case .connectedViaCellular:
                    observer.networkChanged(toState: .online(mobile: true))
                case .connected:
                    observer.networkChanged(toState: .online(mobile: nil))
                case .connectedViaWiFiWithoutInternet, .connectedViaCellularWithoutInternet, .notConnected:
                    observer.networkChanged(toState: .notOnline)
                default:
                    assertionFailure(String(describing: status))
                    break
                }
            }
        }
    }
}

extension NetworkMonitor: NetworkObserverRegister {
    func addObserver(_ observer: NetworkObserver) {
        precondition(Thread.isMainThread)
        let id = ObjectIdentifier(observer)
        networkObservers[id] = NetworkObserverWrapper(observer: observer)
    }

    func removeObserver(_ observer: NetworkObserver) {
        precondition(Thread.isMainThread)
        let id = ObjectIdentifier(observer)
        networkObservers.removeValue(forKey: id)
    }
}

extension NetworkMonitor: NetworkStatusReporter {
    var isOnline: Bool {
        return generalNetworkConnectivity.isConnected && tripupServerConnectivity.isConnected
    }
    var isOnlineViaWiFi: Bool {
        return generalNetworkConnectivity.isConnectedViaWiFi && tripupServerConnectivity.isConnectedViaWiFi
    }
}

extension NetworkMonitor: NetworkMonitorController {
    func refresh() {
        if !started {
            started = true
            generalNetworkConnectivity.startNotifier()
        } else {
            let currentNetworkState = generalNetworkConnectivity.isConnected
            generalNetworkConnectivity.checkConnectivity { [weak self] (connectivity) in
                if currentNetworkState == connectivity.isConnected {    // if general connectivity state hasn't changed, proceed to check if tripup connectivity has
                    self?.checkTripUpServerConnectivity()
                }
            }
        }
    }
}
