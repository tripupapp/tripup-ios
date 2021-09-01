//
//  API.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 08/06/2017.
//  Copyright © 2017 Vinoth Ramiah. All rights reserved.
//

import Foundation
import Alamofire

class API {
    fileprivate class Adapter {
        enum AdapterError: Error {
            case authenticatorNotSet
            case tokenEmpty
            case tokenExpired
        }

        weak var authenticatedUser: AuthenticatedUser?
        var host: String
        private let log = Logger.self
        private let retryPolicy: RetryPolicy = {
            var retryableHTTPMethods = RetryPolicy.defaultRetryableHTTPMethods
            retryableHTTPMethods.insert(.patch)
            return RetryPolicy(retryLimit: 2, exponentialBackoffBase: 3, exponentialBackoffScale: 0.75, retryableHTTPMethods: retryableHTTPMethods)
        }()

        init(for host: String) {
            self.host = host
        }
    }

    weak var authenticatedUser: AuthenticatedUser? {
        get {
            return (session.interceptor as? Adapter)?.authenticatedUser
        }
        set {
            (session.interceptor as? Adapter)?.authenticatedUser = newValue
        }
    }
    var host: String {
        get {
            return (session.interceptor as? Adapter)?.host ?? ""
        }
        set {
            (session.interceptor as? Adapter)?.host = newValue
        }
    }

    private let log = Logger.self
    private let session: Session

    init(host: String) {
        let configuration = URLSessionConfiguration.af.default
        let session = Session(configuration: configuration, interceptor: Adapter(for: host))
        self.session = session
    }

    /**
     NOTE: all API calls are run on a global (default priority) async queue.
     This is because the RequestAdapter `adapt` method for Alamofire version 4 is synchronous, running on the same queue as the one that sessionManagers `request` function is called from.
     Checking the token is a blocking operation, so if an API call was made from main queue, it would cause main to block.
     Might be good to remove/change once Alamofire 5 is released.
    */

    func favouriteImage(params: Parameters, resultHandler: @escaping (_ success: Bool) -> Void) {
        log.debug("")
        DispatchQueue.global().async {
            self.session.request("\(self.host)/album/setfavourite", method: HTTPMethod.put, parameters: params, encoding: JSONEncoding.default).validate().response { response in
                if let error = response.error {
                    self.log.error(error)
                    resultHandler(false)
                } else {
                    resultHandler(true)
                }
            }
        }
    }
}

extension API: LoginAPI {
    func getUUID(callbackOn queue: DispatchQueue, resultHandler: @escaping (Bool, (uuid: UUID, privateKey: String, schemaVersion: String)?) -> Void) {
        log.debug("")
        session.request("\(host)/users/self", method: .get).validate().responseJSON(queue: queue) { response in
            switch response.result {
            case .success(let value):
                if let data = value as? [String: String] {
                    resultHandler(true, (uuid: UUID(uuidString: data["uuid"]!)!, privateKey: data["privatekey"]!, schemaVersion: data["schemaVersion"]!))
                } else {
                    resultHandler(true, nil)
                }
            case .failure(let error):
                self.log.error(error)
                resultHandler(false, nil)
            }
        }
    }

    func createUser(publicKey: String, privateKey: String, callbackOn queue: DispatchQueue, resultHandler: @escaping (Bool, UUID?) -> Void) {
        log.debug("")
        let params: [String: Any] = [
            "publickey": publicKey,
            "privatekey": privateKey
        ]
        session.request("\(host)/users", method: .post, parameters: params, encoding: JSONEncoding.default).validate().responseString(queue: queue) { response in
            switch response.result {
            case .success(let value):
                self.log.info("uuid string returned from server: \(value)")
                resultHandler(true, UUID(uuidString: value))
            case .failure(let error):
                self.log.error(error)
                resultHandler(false, nil)
            }
        }
    }

    func updateContactDetails() {
        log.debug("")
        session.request("\(host)/users/self/contact", method: .put).validate().response() { response in
            if let error = response.error {
                self.log.error(error)
            }
        }
    }
}

extension API: GroupAPI {
    func fetchGroups(callbackOn queue: DispatchQueue, resultHandler: @escaping (Bool, [String: [String: Any]]?) -> Void) {
        log.debug("")
        session.request("\(host)/groups", method: .get).validate().responseJSON(queue: queue) { [log] response in
            switch response.result {
            case .success(let value):
                resultHandler(true, value as? [String: [String: Any]])
            case .failure(let error):
                log.error(error)
                resultHandler(false, nil)
            }
        }
    }

    func joinGroup(id: UUID, groupKeyCipher: String, callbackOn queue: DispatchQueue, resultHandler: @escaping ClosureBool) {
        log.debug("")
        let params = [
            "key": groupKeyCipher,
        ]
        session.request("\(host)/groups/\(id.string)", method: .put, parameters: params, encoding: JSONEncoding.default).validate().response(queue: queue) { [log] response in
            if let error = response.error {
                log.error(error)
                resultHandler(false)
            } else {
                resultHandler(true)
            }
        }
    }

    func fetchAlbumsForAllGroups(callbackOn queue: DispatchQueue, resultHandler: @escaping (Bool, [String: [String: [String]]]?) -> Void) {
        log.debug("")
        session.request("\(host)/groups/album", method: .get).validate().responseJSON(queue: queue) { [log] response in
            switch response.result {
            case .success(let value):
                resultHandler(true, value as? [String: [String: [String]]])
            case .failure(let error):
                log.error(error)
                resultHandler(false, nil)
            }
        }
    }

    func createGroup(name: String, keyStringCipher: String, callbackOn queue: DispatchQueue, resultHandler: @escaping (Bool, UUID?) -> Void) {
        log.debug("")
        let params = [
            "name": name,
            "key": keyStringCipher
        ]
        session.request("\(host)/groups", method: .post, parameters: params, encoding: JSONEncoding.default).validate().responseString(queue: queue) { [log] response in
            switch response.result {
            case .success(let value):
                log.debug("group uuid string returned from server - uuid: \(value)")
                resultHandler(true, UUID(uuidString: value))
            case .failure(let error):
                log.error(error)
                resultHandler(false, nil)
            }
        }
    }

    func leaveGroup(id: UUID, callbackOn queue: DispatchQueue, resultHandler: @escaping ClosureBool) {
        log.debug("")
        session.request("\(host)/groups/\(id.string)", method: .delete, encoding: JSONEncoding.default).validate().response(queue: queue) { [log] response in
            if let error = response.error {
                log.error(error)
                resultHandler(false)
            } else {
                resultHandler(true)
            }
        }
    }

    func amendGroup(id: UUID, invites: [(id: UUID, groupKeyCipher: String)], callbackOn queue: DispatchQueue, resultHandler: @escaping ClosureBool) {
        log.debug("")
        let userData: [[String: String]] = invites.map{[
            "uuid": $0.id.string,
            "key": $0.groupKeyCipher
        ]}
        let params: [String: Any] = [
            "users": userData
        ]
        session.request("\(host)/groups/\(id.string)/users", method: .patch, parameters: params, encoding: JSONEncoding.default).validate().response(queue: queue) { [log] response in
            if let error = response.error {
                log.error(error)
                resultHandler(false)
            } else {
                resultHandler(true)
            }
        }
    }

    func amendGroup(id: UUID, add: Bool, assetIDs: [UUID], callbackOn queue: DispatchQueue, callback: @escaping ClosureBool) {
        log.debug("")
        let params: Parameters = [
            "add": add,
            "assetids": assetIDs.map{ $0.string }
        ]
        session.request("\(host)/groups/\(id.string)/album", method: .patch, parameters: params, encoding: JSONEncoding.default).validate().response(queue: queue) { [log] response in
            if let error = response.error {
                log.error(error)
                callback(false)
            } else {
                callback(true)
            }
        }
    }

    func amendGroup(id: UUID, share: Bool, assetIDs: [UUID], keyStringsForAssets keyStrings: [String]? = nil, callbackOn queue: DispatchQueue, resultHandler: @escaping (_ success: Bool) -> Void) {
        log.debug("")
        var params: Parameters = [
            "share": share,
            "assetids": assetIDs.map{ $0.string }
        ]
        if let keyStrings = keyStrings {
            params["assetkeys"] = keyStrings
        }
        session.request("\(host)/groups/\(id.string)/album/shared", method: .patch, parameters: params, encoding: JSONEncoding.default).validate().response(queue: queue) { [log] response in
            if let error = response.error {
                log.error(error)
                resultHandler(false)
            } else {
                resultHandler(true)
            }
        }
    }

    func fetchUsersInGroup(id: UUID, callbackOn queue: DispatchQueue, resultHandler: @escaping (_ success: Bool, _ users: [String: String]?) -> Void) {
        log.debug("")
        session.request("\(host)/groups/\(id.string)/users", method: .get).validate().responseJSON(queue: queue) { [log] response in
            switch response.result {
            case .success(let value):
                resultHandler(true, value as? [String: String])
            case .failure(let error):
                log.error(error)
                resultHandler(false, nil)
            }
        }
    }
}

extension API: UserAPI {
    func verify<T>(userIDs: T, callbackOn queue: DispatchQueue, callback: @escaping (Bool, [String]?) -> Void) where T: Sequence, T.Element == UUID {
        log.debug("")
        let params: [String: [String]] = [
            "arrayofids": userIDs.map{ $0.string }
        ]
        session.request("\(host)/info/validids", method: .post, parameters: params, encoding: JSONEncoding.default).validate().responseJSON(queue: queue) { response in
            switch response.result {
            case .success(let value):
                self.log.debug("verifyUserIDs - return value: \(value)")
                callback(true, value as? [String])
            case .failure(let error):
                self.log.error(error)
                callback(false, nil)
            }
        }
    }

    func findUser(uuid: String, callbackOn queue: DispatchQueue, callback: @escaping (String?) -> Void) {
        log.debug("")
        session.request("\(host)/users/\(uuid)", method: .get, encoding: JSONEncoding.default).validate().responseString(queue: queue) { response in
            switch response.result {
            case .success(let value):
                self.log.debug("return value: \(value)")
                callback(value)
            case .failure(let error):
                self.log.error(error)
                callback(nil)
            }
        }
    }

    func findUsers(uuids: [String], numbers: [String], emails: [String], callbackOn queue: DispatchQueue, callback: @escaping (Bool, [String: [String : Any]]?) -> Void) {
        log.debug("")
        let params: [String: [String]] = [
            "uuids":    uuids,
            "numbers":  numbers,
            "emails":   emails
        ]
        session.request("\(host)/users/public", method: .post, parameters: params, encoding: JSONEncoding.default).validate().responseJSON(queue: queue) { response in
            switch response.result {
            case .success(let value):
                self.log.verbose("return value: \(value)")
                callback(true, value as? [String: [String : Any]])
            case .failure(let error):
                self.log.error(error)
                callback(false, nil)
            }
        }
    }
}

extension API: AssetAPI {
    func createAsset(params: Parameters, callbackOn queue: DispatchQueue, resultHandler: @escaping (_ success: Bool) -> Void) {
        log.debug("")
        session.request("\(host)/assets", method: .post, parameters: params, encoding: JSONEncoding.default).validate().response(queue: queue) { response in
            if let error = response.error {
                self.log.error(error)
                resultHandler(false)
            } else {
                resultHandler(true)
            }
        }
    }

    func create(assets: [[String: Any]], callbackOn queue: DispatchQueue, resultHandler: @escaping (Result<[String: Int], Error>) -> Void) {
        log.debug("")
        let params: [String: Any] = [
            "CREATE": assets
        ]
        session.request("\(host)/assets", method: .patch, parameters: params, encoding: JSONEncoding.default).validate().responseJSON(queue: queue) { [weak self] response in
            switch response.result {
            case .success(let value as [String: Int]):
                resultHandler(.success(value))
            case .success(Optional<Any>.none):
                resultHandler(.success([String : Int]()))
            case .success(_):
                self?.log.error("invalid return data format")
                resultHandler(.failure("invalid return data format"))
            case .failure(let error):
                self?.log.error(error)
                resultHandler(.failure(error))
            }
        }
    }

    func update(assetID: UUID, originalRemotePath: URL, callbackOn queue: DispatchQueue, resultHandler: @escaping (_ success: Bool) -> Void) {
        log.debug("")
        let params: [String: Any] = [
            "remotepathorig": originalRemotePath.absoluteString
        ]
        session.request("\(host)/assets/\(assetID.string)/original", method: .put, parameters: params, encoding: JSONEncoding.default).validate().response(queue: queue) { response in
            if let error = response.error {
                self.log.error(error)
                resultHandler(false)
            } else {
                resultHandler(true)
            }
        }
    }

    func update(assetsOriginalRemotePaths params: [String: String], callbackOn queue: DispatchQueue, resultHandler: @escaping (_ success: Bool, _ assetsCloudFilesize: [String: Int]?) -> Void) {
        log.debug("")
        session.request("\(host)/assets/original", method: .patch, parameters: params, encoding: JSONEncoding.default).validate().responseJSON(queue: queue) { [weak self] response in
            switch response.result {
            case .success(let value):
                resultHandler(true, value as? [String: Int])
            case .failure(let error):
                self?.log.error(error)
                resultHandler(false, nil)
            }
        }
    }

    func update(originalFilename: String, forAssetID assetID: UUID, callbackOn queue: DispatchQueue, callback: @escaping (_ success: Bool) -> Void) {
        log.debug("")
        let params: [String: String] = [
            "originalfilename": originalFilename
        ]
        session.request("\(host)/assets/\(assetID.string)/originalfilename", method: .put, parameters: params, encoding: JSONEncoding.default).validate().response(queue: queue) { [weak self] response in
            if let error = response.error {
                self?.log.error(error)
                callback(false)
            } else {
                callback(true)
            }
        }
    }

    // [assetID: filename]
    func updateFilenames(_ params: [String: String], callbackOn queue: DispatchQueue, callback: @escaping (_ success: Bool) -> Void) {
        log.debug("")
        session.request("\(host)/assets/originalfilenames", method: .patch, parameters: params, encoding: JSONEncoding.default).validate().response(queue: queue) { [weak self] response in
            if let error = response.error {
                self?.log.error(error)
                callback(false)
            } else {
                callback(true)
            }
        }
    }

    func delete(assetIDs: [String], callbackOn queue: DispatchQueue, resultHandler: @escaping (_ success: Bool) -> Void) {
        log.debug("")
        let params: [String: Any] = [
            "DELETE": assetIDs
        ]
        session.request("\(host)/assets", method: .patch, parameters: params, encoding: JSONEncoding.default).validate().response(queue: queue) { response in
            if let error = response.error {
                self.log.error(error)
                resultHandler(false)
            } else {
                resultHandler(true)
            }
        }
    }

    func getAssets(callbackOn queue: DispatchQueue, resultHandler: @escaping (Bool, [[String: Any]]?) -> Void) {
        log.debug("")
        session.request("\(host)/assets", method: .get).validate().responseJSON(queue: queue) { response in
            switch response.result {
            case .success(let value):
                self.log.debug("Data Returned")
                resultHandler(true, value as? [[String: Any]])
            case .failure(let error):
                self.log.error(error)
                resultHandler(false, nil)
            }
        }
    }
}

extension API: UpgraderAPI {
    func getSchema0Data(callbackOn queue: DispatchQueue, resultHandler: @escaping (Bool, [[String: Any]]?) -> Void) {
        log.debug("")
        session.request("\(host)/schema/0", method: .get).validate().responseJSON(queue: queue) { [log] response in
            switch response.result {
            case .success(let value):
                resultHandler(true, value as? [[String: Any]])
            case .failure(let error):
                log.error(error)
                resultHandler(false, nil)
            }
        }
    }

    func patchSchema0Data(assetKeys: [String: String], assetMD5s: [String: String], callbackOn queue: DispatchQueue, resultHandler: @escaping ClosureBool) {
        log.debug("")
        let params: [String: Any] = [
            "assetkeys": assetKeys,
            "assetmd5s": assetMD5s
        ]
        session.request("\(host)/schema/0", method: .patch, parameters: params, encoding: JSONEncoding.default).validate().response(queue: queue) { [log] response in
            if let error = response.error {
                log.error(error)
                resultHandler(false)
            } else {
                resultHandler(true)
            }
        }
    }
}

extension API.Adapter: RequestInterceptor {
    func adapt(_ urlRequest: URLRequest, for session: Session, completion: @escaping (Result<URLRequest, Error>) -> Void) {
        guard let authenticatedUser = authenticatedUser else {
            completion(.failure(AdapterError.authenticatorNotSet))
            return
        }
        authenticatedUser.token { (token) in
            guard let token = token else { completion(.failure(AdapterError.tokenEmpty)); return }
            guard token.notExpired else { completion(.failure(AdapterError.tokenExpired)); return }
            var urlRequest = urlRequest
            urlRequest.headers.add(.authorization(bearerToken: token.value))
            completion(.success(urlRequest))
        }
    }

    func retry(_ request: Request, for session: Session, dueTo error: Error, completion: @escaping (RetryResult) -> Void) {
        retryPolicy.retry(request, for: session, dueTo: error, completion: completion)
    }
}
