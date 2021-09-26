//
//  AssetActions.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 15/09/2021.
//  Copyright © 2021 Vinoth Ramiah. All rights reserved.
//

import Foundation
import UIKit

protocol AssetActions {
    func export<T>(assets: T, assetRequester: AssetDataRequester, presentingViewController viewController: UIViewController) where T: Collection, T.Element == Asset
    func save<T>(assets: T, assetService: AssetServiceProvider, presentingViewController viewController: UIViewController) where T: Collection, T.Element == Asset
    func saveAllAssets(assetService: AssetServiceProvider, presentingViewController viewController: UIViewController)
    func delete<T>(assets: T, assetService: AssetServiceProvider, presentingViewController viewController: UIViewController, completionHandler: Closure?) where T: Collection, T.Element == Asset
    func deleteOnlineOnlyAssets(assetService: AssetServiceProvider, presentingViewController viewController: UIViewController)
}

extension AssetActions {
    func export<T>(assets: T, assetRequester: AssetDataRequester, presentingViewController viewController: UIViewController) where T: Collection, T.Element == Asset {
        let s = assets.count > 1 ? "s" : ""
        var operationID: UUID?
        let alert = UIAlertController(title: nil, message: "Retrieving \(assets.count) item\(s)", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { (action) in
            if let operationID = operationID {
                assetRequester.cancelOperation(id: operationID)
            }
        }))

        let loadingIndicator = UIActivityIndicatorView(frame: CGRect(x: 10, y: 5, width: 50, height: 50))
        loadingIndicator.hidesWhenStopped = true
        loadingIndicator.style = .medium
        loadingIndicator.startAnimating()
        alert.view.addSubview(loadingIndicator)

        let progressBar = UIProgressView(progressViewStyle: .default)
        alert.view.addSubview(progressBar)

        var completed: Int = 0
        let total: Int = assets.count
        viewController.present(alert, animated: true, completion: { [weak viewController] in
            // configure progress view – must be done after alert is presented
            let margin: CGFloat = 16.0
            let rect = CGRect(x: margin, y: 50.0, width: alert.view.frame.width - margin * 2.0, height: 2.0)
            progressBar.frame = rect

            operationID = assetRequester.requestOriginalFiles(forAssets: assets) { [weak alert, weak viewController] result in
                alert?.dismiss(animated: true, completion: nil)
                switch result {
                case .success(let assets2URLs):
                    let activityController = UIActivityViewController(activityItems: Array(assets2URLs.values), applicationActivities: nil)
                    activityController.completionWithItemsHandler = { [weak viewController] _, _, _, error in
                        if let error = error {
                            viewController?.view.makeToastie("Failed to share \(assets.count) item\(s)", duration: 5.0, position: .top)
                            Logger.error("error exporting assets - assetids: \(assets2URLs.keys.map{ $0.uuid }), error: \(String(describing: error))")
                        }
                    }
                    activityController.excludedActivityTypes = [.saveToCameraRoll]
                    viewController?.present(activityController, animated: true, completion: nil)
                case .failure(let error as AssetManager.OperationError) where error == .cancelled:
                    Logger.verbose("share cancelled - assetids: \(assets.map{ $0.uuid })")
                case .failure(let error):
                    viewController?.view.makeToastie("Failed to retrieve \(assets.count) item\(s)", duration: 7.5, position: .top)
                    Logger.error("error requesting original assets - assetids: \(assets.map{ $0.uuid }), error: \(String(describing: error))")
                }
            } progressHandler: { finished in
                completed += finished
                progressBar.setProgress(Float(completed)/Float(total), animated: true)
            }
        })
    }

    func save<T>(assets: T, assetService: AssetServiceProvider, presentingViewController viewController: UIViewController) where T: Collection, T.Element == Asset {
        let s = assets.count > 1 ? "s" : ""
        var operationID: UUID?
        let alert = UIAlertController(title: nil, message: "Saving \(assets.count) item\(s) to the Photos App", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { (action) in
            if let operationID = operationID {
                assetService.cancelOperation(id: operationID)
            }
        }))

        let loadingIndicator = UIActivityIndicatorView(frame: CGRect(x: 10, y: 5, width: 50, height: 50))
        loadingIndicator.hidesWhenStopped = true
        loadingIndicator.style = .medium
        loadingIndicator.startAnimating()
        alert.view.addSubview(loadingIndicator)

        let progressBar = UIProgressView(progressViewStyle: .default)
        alert.view.addSubview(progressBar)

        var completed: Int = 0
        let total: Int = assets.count
        viewController.present(alert, animated: true, completion: { [weak viewController] in
            operationID = assetService.save(assets: assets, callback: { [weak alert, weak viewController] (result) in
                alert?.dismiss(animated: true, completion: nil)
                var message: String?
                switch result {
                case .success(let alreadySavedAssets):
                    if alreadySavedAssets.count == assets.count {
                        message = "\(assets.count) item\(s) already saved to Photos App"
                    } else {
                        let savedCount = assets.count - alreadySavedAssets.count
                        message = "\(savedCount) item\(savedCount > 1 ? "s" : "") saved to Photos App"
                    }
                case .failure(let error as AssetManager.OperationError) where error == .cancelled:
                    Logger.verbose("save cancelled - assetids: \(assets.map{ $0.uuid })")
                case .failure(let error):
                    message = "Failed to save \(assets.count) item\(s) to Photos App"
                    Logger.error("error saving asset - assetids: \(assets.map{ $0.uuid }), error: \(String(describing: error))")
                }
                if let message = message {
                    viewController?.view.makeToastie(message, duration: 5.0, position: .top)
                }
            }, progressHandler: { finished in
                completed += finished
                progressBar.setProgress(Float(completed)/Float(total), animated: true)
            })
        })
    }

    func saveAllAssets(assetService: AssetServiceProvider, presentingViewController viewController: UIViewController) {
        var operationID: UUID?
        let alert = UIAlertController(title: nil, message: "Saving to Photos App", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { (action) in
            if let operationID = operationID {
                assetService.cancelOperation(id: operationID)
            }
        }))

        let loadingIndicator = UIActivityIndicatorView(frame: CGRect(x: 10, y: 5, width: 50, height: 50))
        loadingIndicator.hidesWhenStopped = true
        loadingIndicator.style = .medium
        loadingIndicator.startAnimating()
        alert.view.addSubview(loadingIndicator)

        let progressBar = UIProgressView(progressViewStyle: .default)
        alert.view.addSubview(progressBar)

        var total: Int = 0
        var completed: Int = 0
        viewController.present(alert, animated: true, completion: { [weak viewController] in
            // configure progress view – must be done after alert is presented
            let margin: CGFloat = 16.0
            let rect = CGRect(x: margin, y: 50.0, width: alert.view.frame.width - margin * 2.0, height: 2.0)
            progressBar.frame = rect

            operationID = assetService.saveAllAssets(initialCallback: { (count) in
                total = count
                progressBar.setProgress(Float(completed)/Float(total), animated: true)
            }, finalCallback: { [weak alert, weak viewController] (result) in
                alert?.dismiss(animated: true, completion: nil)
                var message: String?
                var errorMessage: String?
                switch result {
                case .success(_):
                    message = "Saved all media to the Photos App"
                case .failure(let error as AssetManager.OperationError) where error == .cancelled:
                    Logger.verbose("save all cancelled")
                case .failure(let error):
                    message = "Failed to save all media to the Photos App"
                    errorMessage = String(describing: error)
                    Logger.error("error saving all assets - error: \(errorMessage!)")
                }
                if let message = message {
                    let completionAlert = UIAlertController(title: message, message: errorMessage, preferredStyle: .alert)
                    completionAlert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                    viewController?.present(completionAlert, animated: true, completion: nil)
                }
            }, progressHandler: { (justCompleted) in
                completed += justCompleted
                progressBar.setProgress(Float(completed)/Float(total), animated: true)
            })
        })
    }

    func delete<T>(assets: T, assetService: AssetServiceProvider, presentingViewController viewController: UIViewController, completionHandler: Closure?) where T: Collection, T.Element == Asset {
        let s = assets.count > 1 ? "s" : ""
        let deleteAction = UIAlertAction(title: "Delete", style: .destructive) { _ in
            assetService.delete(assets)
            viewController.view.makeToastie("\(assets.count) item\(s) will be deleted", duration: 7.5)
            completionHandler?()
        }
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel) { _ in }
        let deleteAlert = UIAlertController(title: nil, message: "\(assets.count) item\(s) will be deleted everywhere", preferredStyle: .actionSheet)
        deleteAlert.addAction(deleteAction)
        deleteAlert.addAction(cancelAction)
        viewController.present(deleteAlert, animated: true)
    }

    func deleteOnlineOnlyAssets(assetService: AssetServiceProvider, presentingViewController viewController: UIViewController) {
        assetService.unlinkedAssets(callback: { [weak viewController] (unlinkedAssets) in
            guard unlinkedAssets.isNotEmpty else {
                viewController?.view.makeToastie("There is no online-only content in your cloud storage.", duration: 5.0)
                return
            }
            let photoCount = unlinkedAssets.filter{ $0.value.type == .photo }.count
            let videoCount = unlinkedAssets.filter{ $0.value.type == .video }.count
            assert(unlinkedAssets.count == (photoCount + videoCount))
            let message = "This will remove \(photoCount) photos and \(videoCount) videos from your cloud storage. This action is irreversible."
            let alert = UIAlertController(title: "Are you sure you want to remove online-only content from your cloud storage?", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Yes", style: .destructive, handler: { _ in
                viewController?.view.makeToastie("\(unlinkedAssets.count) items will be removed.", duration: 7.5)
                assetService.removeAssets(ids: unlinkedAssets.keys)
            }))
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            viewController?.present(alert, animated: true, completion: nil)
        })
    }
}
