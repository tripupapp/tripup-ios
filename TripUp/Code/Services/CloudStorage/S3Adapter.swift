//
//  S3Adapter.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 05/11/2021.
//  Copyright © 2021 Vinoth Ramiah. All rights reserved.
//

/*
    swift-nio file streaming examples:
        - https://stackoverflow.com/questions/62540520/how-to-write-a-file-downloaded-with-swiftnio-asynchttpclient-to-the-filesystem
        - https://github.com/vapor/vapor/blob/main/Sources/Vapor/Utilities/FileIO.swift
 */

import Foundation

import SotoCognitoAuthenticationKit
import SotoCognitoIdentity
import SotoCognitoIdentityProvider
import SotoS3
import SotoS3FileTransfer
import SotoSTS
import SotoXML

fileprivate extension STS {
    struct ResponseSanitizer: AWSServiceMiddleware {
        func chain(response: AWSResponse, context: AWSMiddlewareContext) throws -> AWSResponse {
            guard case .xml(let xml) = response.body else {
                throw "Response from AWS service not XML"
            }
            let assumeRoleWithWebIdentityResultKey = xml.elements(forName: "AssumeRoleWithWebIdentityResult").first
            let assumedRoleUserKey = assumeRoleWithWebIdentityResultKey?.elements(forName: "AssumedRoleUser").first

            // ensure `AssumedRoleId` key is present under `AssumedRoleUser` key
            // Soto framework, as of 5.10.0, will reject response if this key is not present
            if assumedRoleUserKey?.elements(forName: "AssumedRoleId").first == nil {
                assumedRoleUserKey?.addChild(XML.Node.element(withName: "AssumedRoleId", stringValue: nil))
            }
            return response
        }
    }

    struct AssumeRoleWithWebIdentityCredentialProvider: CredentialProvider {
        let tokenProvider: (EventLoop) -> EventLoopFuture<String>
        let client: AWSClient
        let sts: STS

        init(tokenProvider: @escaping (EventLoop) -> EventLoopFuture<String>, region: Region, endpoint: String?, httpClient: AWSHTTPClient) {
            self.client = AWSClient(credentialProvider: .empty, middlewares: [ResponseSanitizer()], httpClientProvider: .shared(httpClient))
            self.sts = STS(client: self.client, region: region, endpoint: endpoint)
            self.tokenProvider = tokenProvider
        }

        func getCredential(on eventLoop: EventLoop, logger: Logging.Logger) -> EventLoopFuture<Credential> {
            return tokenProvider(eventLoop).flatMap { token -> EventLoopFuture<STS.AssumeRoleWithWebIdentityResponse> in
                let request = STS.AssumeRoleWithWebIdentityRequest(roleArn: "arn:aws:iam::000000000000:role/Admin", roleSessionName: "now", webIdentityToken: token)
                return self.sts.assumeRoleWithWebIdentity(request, logger: logger, on: eventLoop)
            }.flatMapThrowing { response in
                guard let credentials = response.credentials else { throw CredentialProviderError.noProvider }
                return RotatingCredential(
                    accessKeyId: credentials.accessKeyId,
                    secretAccessKey: credentials.secretAccessKey,
                    sessionToken: credentials.sessionToken,
                    expiration: credentials.expiration
                )
            }
        }

        func shutdown(on eventLoop: EventLoop) -> EventLoopFuture<Void> {
            let promise = eventLoop.makePromise(of: Void.self)
            client.shutdown { error in
                if let error = error {
                    promise.completeWith(.failure(error))
                } else {
                    promise.completeWith(.success(()))
                }
            }
            return promise.futureResult
        }
    }
}

fileprivate extension CredentialProviderFactory {
    static func stsWebIdentity(
        region: Region,
        endpoint: String?,
        tokenProvider: @escaping (EventLoop) -> EventLoopFuture<String>
    ) -> CredentialProviderFactory {
        .custom { context in
            let provider = STS.AssumeRoleWithWebIdentityCredentialProvider(tokenProvider: tokenProvider, region: region, endpoint: endpoint, httpClient: context.httpClient)
            return RotatingCredentialProvider(context: context, provider: provider)
        }
    }
}

class S3Adapter {
    enum S3AdapterError: Error {
        case cognitoIdentityError
        case invalidRegion(String)
        case invalidEndpoint(String)
        case invalidAuthToken
        case s3FileConstructionError
    }

    private struct S3Object {
        let bucket: String
        let ownerID: String
        let object: String

        var key: String {
            return "\(ownerID)/\(object)"
        }

        init(bucket: String, ownerID: String, localURL: URL) {
            self.bucket = bucket
            self.ownerID = ownerID
            self.object = localURL.lastPathComponent
        }

        init(bucket: String, identityID: String, object: String) {
            self.bucket = bucket
            self.ownerID = identityID
            self.object = object
        }

        init(remoteURL: URL) {
            let components = remoteURL.pathComponents
            // components[0] == '/'
            self.bucket = components[1]
            self.ownerID = components[2]
            self.object = components[3]
        }
    }

    private let authenticatedUser: AuthenticatedUser
    private let awsClient: AWSClient
    private let cognitoIdentifiable: CognitoIdentifiable?
    private let s3FileTransferManager: S3FileTransferManager

    private let log = Logger.self
    private let region: String
    private let bucket: String
    private let s3endpoint: URL

    convenience init(authenticatedUser: AuthenticatedUser, region: String, bucket: String, endpoint: String?, awsCognito: (identityPoolID: String, federationProvider: String)?) throws {
        guard let awsRegion = Region(awsRegionName: region) else {
            throw S3AdapterError.invalidRegion(region)
        }

        let credentialProvider: CredentialProviderFactory
        if let awsCognito = awsCognito {
            credentialProvider = .cognitoIdentity(
                identityPoolId: awsCognito.identityPoolID,
                identityProvider: .externalIdentityProvider(tokenProvider: { context in
                    let promise = context.eventLoop.makePromise(of: [String: String].self)
                    authenticatedUser.token { token in
                        if let token = token, token.notExpired {
                            promise.succeed([awsCognito.federationProvider: token.value])
                        } else {
                            promise.fail(S3AdapterError.invalidAuthToken)
                        }
                    }
                    return promise.futureResult
                }),
                region: awsRegion
            )
        } else {
            credentialProvider = .stsWebIdentity(region: awsRegion, endpoint: endpoint) { eventLoop in
                let promise = eventLoop.makePromise(of: String.self)
                authenticatedUser.token { token in
                    if let token = token, token.notExpired {
                        promise.succeed(token.value)
                    } else {
                        promise.fail(S3AdapterError.invalidAuthToken)
                    }
                }
                return promise.futureResult
            }
        }

        try self.init(credentialProvider: credentialProvider, authenticatedUser: authenticatedUser, region: awsRegion, bucket: bucket, endpoint: endpoint, awsCognito: awsCognito)
    }

    private init(credentialProvider: CredentialProviderFactory, authenticatedUser: AuthenticatedUser, region: Region, bucket: String, endpoint: String?, awsCognito: (identityPoolID: String, federationProvider: String)?) throws {

        // TODO: https://aws.amazon.com/blogs/aws/amazon-s3-path-deprecation-plan-the-rest-of-the-story/
        let endpointString = endpoint ?? "https://s3.\(region.rawValue).amazonaws.com"
        guard let endpointURL = URL(string: endpointString) else {
            throw S3AdapterError.invalidEndpoint(endpointString)
        }
        self.s3endpoint = endpointURL

        self.authenticatedUser = authenticatedUser
        self.awsClient = AWSClient(credentialProvider: credentialProvider, retryPolicy: .default, httpClientProvider: .createNew)
        if let awsCognito = awsCognito {
            let cognitoIdentity = CognitoIdentity(client: awsClient, region: region, endpoint: endpoint)
            let configuration = CognitoIdentityConfiguration(identityPoolId: awsCognito.identityPoolID, identityProvider: awsCognito.federationProvider, cognitoIdentity: cognitoIdentity)
            self.cognitoIdentifiable = CognitoIdentifiable(configuration: configuration)
        } else {
            self.cognitoIdentifiable = nil
        }

        let s3ServiceObject = S3(client: awsClient, region: region, endpoint: endpoint)
        self.s3FileTransferManager = S3FileTransferManager(s3: s3ServiceObject, threadPoolProvider: .createNew)

        self.region = region.rawValue
        self.bucket = bucket
    }

    deinit {
        try? awsClient.syncShutdown()
    }

    private func ownerID(callback: @escaping (Result<String, S3AdapterError>) -> Void) {
        if let cognitoIdentifiable = cognitoIdentifiable {
            authenticatedUser.token { [weak self] token in
                if let token = token, token.notExpired {
                    cognitoIdentifiable.getIdentityId(idToken: token.value).whenComplete { [weak self] result in
                        switch result {
                        case .success(let id):
                            callback(.success(id))
                        case .failure(let error):
                            self?.log.error("unable to obtain cognito ID - error: \(String(describing: error))")
                            callback(.failure(.cognitoIdentityError))
                        }
                    }
                } else {
                    self?.log.error(S3AdapterError.invalidAuthToken)
                    callback(.failure(.invalidAuthToken))
                }
            }
        } else {
            callback(.success(authenticatedUser.id))
        }
    }
}

extension S3Adapter: DataService {
    func deleteFile(at url: URL, callback: @escaping (_ success: Bool) -> Void) {
        fatalError("disabled")
    }

    func delete(_ object: String, callback: @escaping (_ success: Bool) -> Void) {
        fatalError("disabled")
    }

    func uploadFile(at url: URL, callback: @escaping (_ url: URL?) -> Void) {
        ownerID { [weak self] result in
            guard let self = self else {
                return
            }
            switch result {
            case .success(let ownerID):
                let s3object = S3Object(bucket: self.bucket, ownerID: ownerID, localURL: url)

                if let s3File = S3File(url: "s3://\(s3object.bucket)/\(s3object.key)") {
                    let options: S3FileTransferManager.PutOptions
                    if self.s3endpoint.absoluteString == "https://s3.\(self.region).amazonaws.com" {
                        #if DEBUG
                        options = .init(storageClass: .standard)
                        #else
                        options = .init(storageClass: .standardIa)
                        #endif
                    } else {
                        options = .init()   // custom endpoint, so don't set storage class
                    }
                    self.s3FileTransferManager.copy(from: url.path, to: s3File, options: options).whenComplete { [log = self.log, s3endpoint = self.s3endpoint] result in
                        switch result {
                        case .success:
                            let publicURL = s3endpoint.appendingPathComponent(s3object.bucket).appendingPathComponent(s3object.key)
                            log.debug("uploaded - bucket: \(s3object.bucket), key: \(s3object.key), fullURL: \(publicURL.absoluteString)")
                            callback(publicURL)
                        case .failure(let error):
                            log.error("upload failed - bucket: \(s3object.bucket), key: \(s3object.key), error: \(String(describing: error))")
                            callback(nil)
                        }
                    }
                } else {
                    self.log.error("download failed - bucket: \(s3object.bucket), key: \(s3object.key), error: \(S3AdapterError.s3FileConstructionError)")
                    callback(nil)
                }
            case .failure(let error):
                self.log.error("failed to get s3ID - error: \(String(describing: error))")
                callback(nil)
            }
        }
    }

    func downloadFile(at remotePath: URL, to url: URL, callback: @escaping (Bool) -> Void) {
        let s3object = S3Object(remoteURL: remotePath)
        if let s3File = S3File(url: "s3://\(s3object.bucket)/\(s3object.key)") {
            s3FileTransferManager.copy(from: s3File, to: url.path).whenComplete { [log] result in
                switch result {
                case .success:
                    callback(true)
                case .failure(let error):
                    log.error("download failed - bucket: \(s3object.bucket), key: \(s3object.key), error: \(String(describing: error))")
                    callback(false)
                }
            }
        } else {
            log.error("download failed - bucket: \(s3object.bucket), key: \(s3object.key), error: \(S3AdapterError.s3FileConstructionError)")
            callback(false)
        }
    }
}
