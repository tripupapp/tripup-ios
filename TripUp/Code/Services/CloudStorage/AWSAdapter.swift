//
//  AWSAdapter.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 20/07/2017.
//  Copyright © 2017 Vinoth Ramiah. All rights reserved.
//

import Foundation

import AWSCore
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

    private class AWSOIDCProvider: NSObject, AWSIdentityProviderManager {
        enum AWSOIDCProviderError: Error {
            case tokenInvalid
            case oidcProviderDeinited
        }

        private let authenticatedUser: AuthenticatedUser
        private let oidcProviderName: String
        private let log = Logger.self

        init(authenticatedUser: AuthenticatedUser, oidcProviderName: String) {
            self.authenticatedUser = authenticatedUser
            self.oidcProviderName = oidcProviderName
        }

        func logins() -> AWSTask<NSDictionary> {
            let taskCompletion = AWSTaskCompletionSource<NSString>()
            authenticatedUser.token { token in
                if let token = token, token.notExpired {
                    taskCompletion.set(result: token.value as NSString)
                } else {
                    taskCompletion.set(error: AWSOIDCProviderError.tokenInvalid)
                }
            }

            return taskCompletion.task.continueOnSuccessWith { [weak self] task -> AWSTask<NSDictionary>? in
                guard let self = self else {
                    return AWSTask(error: AWSOIDCProviderError.oidcProviderDeinited)
                }
                if let token = task.result {
                    return AWSTask(result: [self.oidcProviderName: token])
                } else {
                    self.log.error(String(describing: task.error!))
                    return AWSTask(error: task.error!)
                }
            } as! AWSTask<NSDictionary>
        }
    }

    private let log = Logger.self
    private let transferUtilityKey = "transfer-utility-with-advanced-options"
    private let retryLimit = 1      // retry one time - default value is 0
    private let timeout = 50 * 60   // 50 minute timeout - default value
    private let oidcProvider: AWSOIDCProvider
    private let region: String
    private let bucket: String
    private let s3endpoint: URL
    private let credentialsProvider: AWSCognitoCredentialsProvider
    private let uploadCallbackQueue = DispatchQueue(label: String(describing: AWSAdapter.self) + ".uploadCallback", qos: .default, target: DispatchQueue.global())

    init(authenticatedUser: AuthenticatedUser, federationProvider: String, identityPoolID: String, region: String, bucket: String) throws {
        let awsRegion: AWSRegionType
        switch region {
        case "eu-west-2":
            awsRegion = .EUWest2
        default:
            throw "invalid region - \(region)"
        }

        self.oidcProvider = AWSOIDCProvider(authenticatedUser: authenticatedUser, oidcProviderName: federationProvider)
        self.region = region
        self.bucket = bucket
        // TODO: https://aws.amazon.com/blogs/aws/amazon-s3-path-deprecation-plan-the-rest-of-the-story/
        self.s3endpoint = URL(string: "https://s3.\(region).amazonaws.com")!

//        credentialsProvider = AWSStaticCredentialsProvider(accessKey: accessKey, secretKey: secretKey)
        credentialsProvider = AWSCognitoCredentialsProvider(regionType: awsRegion, identityPoolId: identityPoolID, identityProviderManager: oidcProvider)
        let configuration = AWSServiceConfiguration(region: awsRegion, credentialsProvider: credentialsProvider)!
        AWSServiceManager.default().defaultServiceConfiguration = configuration

        let transferConfig = AWSS3TransferUtilityConfiguration()
        transferConfig.retryLimit = retryLimit
        transferConfig.timeoutIntervalForResource = timeout
        AWSS3TransferUtility.register(with: configuration, transferUtilityConfiguration: transferConfig, forKey: transferUtilityKey) { error in
            if let error = error {
                fatalError(String(describing: error))
            }
        }
    }

    deinit {
        AWSS3TransferUtility.remove(forKey: transferUtilityKey)
        credentialsProvider.clearKeychain()
    }

    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        // Store the completion handler.
        AWSS3TransferUtility.interceptApplication(application, handleEventsForBackgroundURLSession: identifier, completionHandler: completionHandler)
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
        credentialsProvider.getIdentityId().continueOnSuccessWith { [log, transferUtilityKey, bucket, s3endpoint] task -> Any? in
            guard let transferUtility = AWSS3TransferUtility.s3TransferUtility(forKey: transferUtilityKey) else {
                log.error("can't find transfer utility with key: \(transferUtilityKey)")
                callback(nil)
                return nil
            }
            let s3object = AWSS3Object(bucket: bucket, identityID: task.result! as String, localURL: url)

            // because AWS SDK sucks, so need to have this to prevent SDK from calling completion handler multiple times on (multipart) failure
            let completionCalled = MutableReference(value: false)
            let completionHandler: (Any, Error?) -> Void = { [log, s3endpoint] (_, error) in
                self.uploadCallbackQueue.async {
                    guard !completionCalled.value else {
                        return
                    }
                    if let error = error {
                        log.error("upload failed - bucket: \(s3object.bucket), key: \(s3object.key), error: \(String(describing: error))")
                        callback(nil)
                    } else {
                        let publicURL = s3endpoint.appendingPathComponent(s3object.bucket).appendingPathComponent(s3object.key)
                        log.debug("uploaded - bucket: \(s3object.bucket), key: \(s3object.key), fullURL: \(publicURL.absoluteString)")
                        callback(publicURL)
                    }
                    completionCalled.update(with: true)
                }
            }
            let attr = try? FileManager.default.attributesOfItem(atPath: url.path)
            if let fileSize = attr?[FileAttributeKey.size] as? UInt64, fileSize >= 5242880 {    // use multipart upload for files larger than 5 MB
                let expression = AWSS3TransferUtilityMultiPartUploadExpression()
                #if DEBUG
                #else
                expression.setValue("STANDARD_IA", forRequestHeader: "x-amz-storage-class")
                #endif
                return transferUtility.uploadUsingMultiPart(fileURL: url, bucket: s3object.bucket, key: s3object.key, contentType: "application/octet-stream", expression: expression, completionHandler: completionHandler)
            } else {
                let expression = AWSS3TransferUtilityUploadExpression()
                #if DEBUG
                #else
                expression.setValue("STANDARD_IA", forRequestHeader: "x-amz-storage-class")
                #endif
                return transferUtility.uploadFile(url, bucket: s3object.bucket, key: s3object.key, contentType: "application/octet-stream", expression: expression, completionHandler: completionHandler)
            }
        }.continueWith { [log] task -> Any? in
            switch (task.result, task.error) {
            case (let task as AWSS3TransferUtilityUploadTask, .none):
                log.verbose("upload started – bucket: \(task.bucket), key: \(task.key), fileURL: \(String(describing: url))")
            case (let task as AWSS3TransferUtilityMultiPartUploadTask, .none):
                log.verbose("upload started – bucket: \(task.bucket), key: \(task.key), fileURL: \(String(describing: url))")
            case (let task as AWSS3TransferUtilityUploadTask, .some(let error)):
                log.error("failed to initialise upload – bucket: \(task.bucket), key: \(task.key), fileURL: \(String(describing: url)), error: \(String(describing: error))")
                log.verbose((error as NSError).userInfo)
                callback(nil)
            case (let task as AWSS3TransferUtilityMultiPartUploadTask, .some(let error)):
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
