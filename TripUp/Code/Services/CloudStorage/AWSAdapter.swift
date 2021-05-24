//
//  AWSAdapter.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 20/07/2017.
//  Copyright © 2017 Vinoth Ramiah. All rights reserved.
//

import Foundation

import AWSCore
import AWSMobileClient
import AWSS3

class AWSAdapter {
    private struct AWSS3Object {
        let bucket: String
        let ownerIdentityID: String
        let object: String

        var key: String {
            return "\(ownerIdentityID)/\(object)"
        }

        init(bucket: String, identityID: String, localURL: URL) {
            self.bucket = bucket
            self.ownerIdentityID = identityID
            self.object = localURL.lastPathComponent
        }

        init(bucket: String, identityID: String, object: String) {
            self.bucket = bucket
            self.ownerIdentityID = identityID
            self.object = object
        }

        init(remoteURL: URL) {
            let components = remoteURL.pathComponents
            // components[0] == '/'
            self.bucket = components[1]
            self.ownerIdentityID = components[2]
            self.object = components[3]
        }
    }

    weak var authenticatedUser: APIUser? {
        didSet {
            process(AWSMobileClient.default().currentUserState)
        }
    }
    var bucket: String?
    var federationProviderName: String?
    var region: String?

    private let log = Logger.self
    private let transferUtilityKey = "transfer-utility-with-advanced-options"
    private let retryLimit = 3
    private let timeout = 15 * 60
    private let listenerToken = NSObject()

    // TODO: https://aws.amazon.com/blogs/aws/amazon-s3-path-deprecation-plan-the-rest-of-the-story/
    private var s3endpoint: URL {
        return URL(string: "https://s3.\(region!).amazonaws.com")!
    }

    init() {
        AWSMobileClient.default().initialize { [weak self] initialUserState, error in
            guard let self = self else { return }
            if let initialUserState = initialUserState {
                self.log.debug("AWSMobileClient initialised – userState: \(String(describing: initialUserState))")
            } else if let error = error {
                fatalError(String(describing: error))
            }
            AWSMobileClient.default().addUserStateListener(self.listenerToken) { [unowned self] userState, info in
                self.process(userState)
            }
            let transferConfig = AWSS3TransferUtilityConfiguration()
            transferConfig.retryLimit = self.retryLimit
            transferConfig.timeoutIntervalForResource = self.timeout
            let configuration = AWSServiceConfiguration(region: .EUWest2, credentialsProvider: AWSMobileClient.default())!
            AWSS3TransferUtility.register(with: configuration, transferUtilityConfiguration: transferConfig, forKey: self.transferUtilityKey) { error in
                if let error = error {
                    fatalError(String(describing: error))
                }
            }
//            AWSServiceManager.default()!.defaultServiceConfiguration = configuration    // needed for AWS services other than AWSS3TransferUtility, like AWSS3.default()
        }
    }

    deinit {
        AWSS3TransferUtility.remove(forKey: transferUtilityKey)
        AWSMobileClient.default().removeUserStateListener(listenerToken)
    }

    func signOut() {
        authenticatedUser = nil
        AWSMobileClient.default().signOut()
        AWSMobileClient.default().invalidateCachedTemporaryCredentials()
        log.debug("AWSMobileClient signed out – userState: \(String(describing: AWSMobileClient.default().currentUserState))")
    }

    private func process(_ userState: UserState) {
        guard let authenticatedUser = authenticatedUser else { log.verbose("authenticatedUser nil"); return }
        switch userState {
        case .guest, .signedOut, .signedOutFederatedTokensInvalid:
            log.debug("aws user state is: \(String(describing: userState)), need to (re)authenticate")
            authenticatedUser.token { [weak self] token in
                guard let self = self else {
                    return
                }
                guard let federationProviderName = self.federationProviderName else {
                    self.log.error("no providerName set")
                    return
                }
                guard let token = token, token.notExpired else {
                    self.log.error("token from APIUser is invalid")
                    return
                }
                AWSMobileClient.default().federatedSignIn(providerName: federationProviderName, token: token.value) { [log = self.log] federatedState, federatedError in
                    log.debug("aws user state is now: \(String(describing: federatedState))")
                    if federatedState == .none || federatedState != .some(.signedIn) {
                        log.error(federatedError?.localizedDescription ?? "federated sign in failed. state is: \(String(describing: federatedState))")
                    }
                }
            }
        case .signedIn:
            break
        default:
            log.error("aws user state: \(userState) is unsupported")
        }
    }
}

extension AWSAdapter: DataService {
    func deleteFile(at url: URL, callback: @escaping (_ success: Bool) -> Void) {
        fatalError("disabled")
//        let s3object = AWSS3Object(remoteURL: url)
//        let request = AWSS3DeleteObjectRequest()!
//        request.bucket = s3object.bucket
//        request.key = s3object.key
//        AWSS3.default().deleteObject(request).continueWith { task -> Any? in
//            if let error = task.error {
//                self.log.error("delete failed - bucket: \(s3object.bucket), key: \(s3object.key), error: \(String(describing: error))")
//                callback(false)
//            } else {
//                self.log.info("deleted - bucket: \(s3object.bucket), key: \(s3object.key)")
//                callback(true)
//            }
//            return nil
//        }
    }

    func delete(_ object: String, callback: @escaping (_ success: Bool) -> Void) {
        fatalError("disabled")
//        var s3object: AWSS3Object?
//        AWSMobileClient.default().getIdentityId().continueOnSuccessWith { task -> Any? in
//            s3object = AWSS3Object(bucket: self.bucket, identityID: task.result! as String, object: object)
//            let request = AWSS3DeleteObjectRequest()!
//            request.bucket = s3object!.bucket
//            request.key = s3object!.key
//            return AWSS3.default().deleteObject(request)
//        }.continueWith { task -> Any? in
//            switch (task.result, task.error) {
//            case (is AWSS3DeleteObjectOutput , .none):
//                self.log.info("deleted - bucket: \(s3object!.bucket), key: \(s3object!.key)")
//                callback(true)
//            case (is AWSS3DeleteObjectOutput, .some(let error)):
//                self.log.error("delete failed - bucket: \(s3object!.bucket), key: \(s3object!.key), error: \(String(describing: error))")
//                callback(false)
//            case (_, .some(let error)):
//                self.log.error(String(describing: error))
//                callback(false)
//            default:
//                break
//            }
//            return nil
//        }
    }

    func uploadFile(at url: URL, callback: @escaping (_ url: URL?) -> Void) {
        AWSMobileClient.default().getIdentityId().continueOnSuccessWith { [log, transferUtilityKey, bucket, s3endpoint] task -> Any? in
            guard let transferUtility = AWSS3TransferUtility.s3TransferUtility(forKey: transferUtilityKey) else {
                log.error("can't find transfer utility with key: \(transferUtilityKey)")
                callback(nil)
                return nil
            }
            guard let bucket = bucket else {
                log.error("bucket not set")
                callback(nil)
                return nil
            }
            let s3object = AWSS3Object(bucket: bucket, identityID: task.result! as String, localURL: url)
            let expression = AWSS3TransferUtilityUploadExpression()
            #if DEBUG
            #else
            expression.setValue("STANDARD_IA", forRequestHeader: "x-amz-storage-class")
            #endif
            return transferUtility.uploadFile(url, bucket: s3object.bucket, key: s3object.key, contentType: "application/octet-stream", expression: expression) { [log, s3endpoint] (task, error) in
                if let error = error {
                    log.error("upload failed - bucket: \(s3object.bucket), key: \(s3object.key), error: \(String(describing: error))")
                    callback(nil)
                } else {
                    let publicURL = s3endpoint.appendingPathComponent(s3object.bucket).appendingPathComponent(s3object.key)
                    log.debug("uploaded - bucket: \(s3object.bucket), key: \(s3object.key), fullURL: \(publicURL.absoluteString)")
                    callback(publicURL)
                }
            }
        }.continueWith { [log] task -> Any? in
            switch (task.result, task.error) {
            case (let task as AWSS3TransferUtilityUploadTask, .none):
                log.verbose("upload started – bucket: \(task.bucket), key: \(task.key), fileURL: \(String(describing: url))")
            case (let task as AWSS3TransferUtilityUploadTask, .some(let error)):
                log.error("failed to initialise upload – bucket: \(task.bucket), key: \(task.key), fileURL: \(String(describing: url)), error: \(String(describing: error))")
                log.verbose((error as NSError).userInfo)
                callback(nil)
            case (_, .some(let error)):
                log.error(String(describing: error))
                callback(nil)
            default:
                log.error("unexpected result: \(String(describing: task))")
                break
            }
            return nil
        }
    }

    func downloadFile(at remotePath: URL, to url: URL, callback: @escaping (Bool) -> Void) {
        guard let transferUtility = AWSS3TransferUtility.s3TransferUtility(forKey: transferUtilityKey) else {
            log.error("can't find transfer utility with key: \(transferUtilityKey)")
            callback(false)
            return
        }
        let s3object = AWSS3Object(remoteURL: remotePath)
        transferUtility.download(to: url, bucket: s3object.bucket, key: s3object.key, expression: nil) { [log] _, localURL, _, error in
            if let error = error {
                log.error("download failed - bucket: \(s3object.bucket), key: \(s3object.key), error: \(String(describing: error))")
                callback(false)
            } else {
                assert(localURL == url)
                log.debug("downloaded - bucket: \(s3object.bucket), key: \(s3object.key), path: \(url.path)")
                callback(true)
            }
        }.continueWith { [log] task -> Any? in
            if let error = task.error {
                log.error("failed to initialise download - bucket: \(s3object.bucket), key: \(s3object.key), error: \(String(describing: error))")
                log.verbose((error as NSError).userInfo)
                callback(false)
            } else {
                log.verbose("download started - bucket: \(s3object.bucket), key: \(s3object.key), path: \(remotePath.path)")
            }
            return nil
        }
    }
}
