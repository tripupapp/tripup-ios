//
//  PreferencesView.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 03/02/2020.
//  Copyright © 2020 Vinoth Ramiah. All rights reserved.
//

import Foundation
import UIKit

import Charts
import PhoneNumberKit

class PreferencesView: UITableViewController {
    @IBOutlet var backupSwitch: UISwitch!
    @IBOutlet var chartView: HorizontalBarChartView!
    @IBOutlet var storageLabel: UILabel!

    private weak var appDelegateExtension: AppDelegateExtension?
    private var primaryUser: User!
    private var appContextInfo: AppContextInfo?
    private var purchasesController: PurchasesController!
    private var dependencyInjector: DependencyInjector!

    func initialise(primaryUser: User, appContextInfo: AppContextInfo?, purchasesController: PurchasesController, appDelegateExtension: AppDelegateExtension?, dependencyInjector: DependencyInjector) {
        self.primaryUser = primaryUser
        self.appContextInfo = appContextInfo
        self.purchasesController = purchasesController
        self.appDelegateExtension = appDelegateExtension
        self.dependencyInjector = dependencyInjector

        purchasesController.addObserver(self)

        if #available(iOS 13.0, *) {
            tabBarItem?.image = UIImage(systemName: "gear")
        }
    }

    deinit {
        purchasesController.removeObserver(self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        #if DEBUG
        let screenshotEnv = ProcessInfo.processInfo.environment["UITest-Screenshots"] != nil
        backupSwitch.setOn(UserDefaults.standard.bool(forKey: UserDefaultsKey.AutoBackup.rawValue) || screenshotEnv, animated: false)
        #else
        backupSwitch.setOn(UserDefaults.standard.bool(forKey: UserDefaultsKey.AutoBackup.rawValue), animated: false)
        #endif
        purchasesController.entitled { [weak self] storageTier in
            self?.drawStorage(tier: storageTier)
        }
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        super.prepare(for: segue, sender: sender)

        switch segue.destination {
        case let authenticationView as AuthenticationView:
            dependencyInjector.initialise(authenticationView: authenticationView)
        case let securityView as SecurityView:
            dependencyInjector.initialise(securityView: securityView)
        case let cloudStorageVC as CloudStorageVC:
            dependencyInjector.initialise(cloudStorageVC)
            cloudStorageVC.showFreeButton = false
        case let inAppPurchaseView as InAppPurchaseView:
            dependencyInjector.initialise(inAppPurchaseView: inAppPurchaseView)
        default:
            break
        }
    }

    override func tableView(_ tableView: UITableView, accessoryButtonTappedForRowWith indexPath: IndexPath) {
        switch (indexPath.section, indexPath.item) {
        case (1, 2):    // Delete online-only content
            let message = """
            This will remove all photos and videos that aren't present on your phone from your cloud backup.

            This is useful if you've deleted some content from the Photos app and would like those changes reflected in TripUp.

            Online-only content will be removed from all albums. This does not affect content that has been shared with you by others.
            """
            let alert = UIAlertController(title: "", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
            self.present(alert, animated: true, completion: nil)
        default:
            break
        }
    }

    override func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        switch (indexPath.section, indexPath.item) {
        case (1, 1):    // auto backup switch toggle
            return nil
        default:
            return indexPath
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        switch (indexPath.section, indexPath.item) {
        case (0, 0):    // Share profile link
            view.makeToastieActivity(true)
            UniversalLinksService.shared.generate(forUser: primaryUser) { (url) in
                if let url = url {
                    let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                    self.present(activityVC, animated: true)
                } else {
                    self.view.makeToastie("Unable to generate your personal link. Please try again.")
                }
                self.view.makeToastieActivity(false)
                self.tableView.deselectRow(at: indexPath, animated: false)
            }
        case (1, 2):    // Delete online-only content
            deleteOnlineOnlyContent()
            tableView.deselectRow(at: indexPath, animated: false)
        case (1, 3):    // Save all to Photos App
            presentSaveAllAlert()
            tableView.deselectRow(at: indexPath, animated: false)
        case (3, 1):    // Legal
            legal()
            tableView.deselectRow(at: indexPath, animated: false)
        case (5, 0):    // Sign Out
            signOut()
            tableView.deselectRow(at: indexPath, animated: false)
        default:
            break
        }
    }

    @IBAction func unwindAction(_ unwindSegue: UIStoryboardSegue) {}

    @IBAction func backupSwitchToggled(_ sender: UISwitch) {
        UserDefaults.standard.set(sender.isOn, forKey: UserDefaultsKey.AutoBackup.rawValue)
        NotificationCenter.default.post(name: .AutoBackupChanged, object: sender.isOn)
    }

    private func deleteOnlineOnlyContent() {
        appContextInfo?.assetUIManager.unlinkedAssets(callback: { [weak self] (unlinkedAssets) in
            guard unlinkedAssets.isNotEmpty else {
                self?.view.makeToastie("There is no online-only content in your cloud storage.", duration: 5.0)
                return
            }
            let photoCount = unlinkedAssets.filter{ $0.value.type == .photo }.count
            let videoCount = unlinkedAssets.filter{ $0.value.type == .video }.count
            assert(unlinkedAssets.count == (photoCount + videoCount))
            let message = "This will remove \(photoCount) photos and \(videoCount) videos from your cloud storage. This action is irreversible."
            let alert = UIAlertController(title: "Are you sure you want to remove online-only content from your cloud storage?", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Yes", style: .destructive, handler: { _ in
                self?.view.makeToastie("\(unlinkedAssets.count) items will be removed.", duration: 7.5)
                self?.appContextInfo?.assetUIManager.removeAssets(ids: unlinkedAssets.keys)
            }))
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            self?.present(alert, animated: true, completion: nil)
        })
    }

    private func presentSaveAllAlert() {
        let alert = UIAlertController(title: "Save all media in TripUp to the Photos App?", message: nil, preferredStyle: .alert)
        let saveAction = UIAlertAction(title: "Yes", style: .default) { [weak self] (_) in
            self?.saveAllToPhotosApp()
        }
        alert.addAction(saveAction)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        present(alert, animated: true, completion: nil)
    }

    private func saveAllToPhotosApp() {
        var operationID: UUID?
        let alert = UIAlertController(title: nil, message: "Saving to Photos App", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { [weak self] (action) in
            if let operationID = operationID {
                self?.appContextInfo?.assetUIManager.cancelOperation(id: operationID)
            }
        }))

        let loadingIndicator = UIActivityIndicatorView(frame: CGRect(x: 10, y: 5, width: 50, height: 50))
        loadingIndicator.hidesWhenStopped = true
        loadingIndicator.style = UIActivityIndicatorView.Style.gray
        loadingIndicator.startAnimating()
        alert.view.addSubview(loadingIndicator)

        let progressBar = UIProgressView(progressViewStyle: .default)
        alert.view.addSubview(progressBar)

        var total: Int = 0
        var completed: Int = 0
        present(alert, animated: true, completion: { [weak self] in
            // configure progress view – must be done after alert is presented
            let margin: CGFloat = 16.0
            let rect = CGRect(x: margin, y: 50.0, width: alert.view.frame.width - margin * 2.0, height: 2.0)
            progressBar.frame = rect

            operationID = self?.appContextInfo?.assetUIManager.saveAllAssets(initialCallback: { (count) in
                total = count
                progressBar.setProgress(Float(completed)/Float(total), animated: true)
            }, finalCallback: { [weak self, weak alert] (result) in
                alert?.dismiss(animated: true, completion: nil)
                var message: String?
                var errorMessage: String?
                switch result {
                case .success(_):
                    message = "Saved all media to the Photos App"
                case .failure(let error as AssetManager.OperationError) where error == .cancelled:
                    Logger.self.verbose("save all cancelled")
                case .failure(let error):
                    message = "Failed to save all media to the Photos App"
                    errorMessage = String(describing: error)
                    Logger.self.error("error saving all assets - error: \(errorMessage!)")
                }
                if let message = message {
                    let completionAlert = UIAlertController(title: message, message: errorMessage, preferredStyle: .alert)
                    completionAlert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                    self?.present(completionAlert, animated: true, completion: nil)
                }
            }, progressHandler: { (justCompleted) in
                completed += justCompleted
                progressBar.setProgress(Float(completed)/Float(total), animated: true)
            })
        })
    }

    private func legal() {
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "EULA", style: .default, handler: { _ in
            let url = Bundle.main.url(forResource: "eula", withExtension: "html")!
            let vc = UIStoryboard(name: "Policy", bundle: nil).instantiateInitialViewController() as! PolicyView
            vc.initialise(title: "EULA", url: url)
            self.navigationController?.pushViewController(vc, animated: true)
        }))
        alert.addAction(UIAlertAction(title: "Privacy Policy", style: .default, handler: { _ in
            let url = Globals.Directories.legal.appendingPathComponent(Globals.Documents.privacyPolicy.renderedFilename, isDirectory: false)
            let vc = UIStoryboard(name: "Policy", bundle: nil).instantiateInitialViewController() as! PolicyView
            vc.initialise(title: "Privacy Policy", url: url)
            self.navigationController?.pushViewController(vc, animated: true)
        }))
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true, completion: nil)
    }

    private func signOut() {
        let alert = UIAlertController(title: "Are you sure you want to sign out?", message: "Please ensure you've made a backup of your account password, visible from the Password menu.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Yes", style: .destructive, handler: { _ in
            self.appDelegateExtension?.presentNextRootViewController(after: self, fadeIn: true, resetApp: true)
        }))
        alert.addAction(UIAlertAction(title: "No", style: .cancel, handler: nil))
        present(alert, animated: true, completion: nil)
    }
}

extension PreferencesView {
    private func drawStorage(tier storageTier: StorageTier) {
        guard let storageLabel = storageLabel else { return }
        appContextInfo?.usedStorage { [weak self] (usedStorage) in
            guard let usedStorage = usedStorage else {
                return
            }
            storageLabel.text = "\(ByteCountFormatter.string(fromByteCount: usedStorage.totalSize, countStyle: .binary)) of \(String(describing: storageTier)) Used"
            self?.drawStorageChart(usedStorage: usedStorage, availableStorage: Double(storageTier.size))
        }
    }

    private func drawStorageChart(usedStorage: UsedStorage, availableStorage: Double) {
        let labels = [
            "\(usedStorage.photos.count) Photos",
            "\(usedStorage.videos.count) Videos"
        ]
        let values = [
            Double(usedStorage.photos.totalSize),
            Double(usedStorage.videos.totalSize)
        ]

        let dataEntries = [BarChartDataEntry(x: 0, yValues: values)]
        let chartDataSet = BarChartDataSet(entries: dataEntries, label: nil)
        chartDataSet.stackLabels = labels
        chartDataSet.colors = [.systemYellow, .systemRed]
        chartDataSet.drawValuesEnabled = false

        let chartData = BarChartData(dataSet: chartDataSet)
        chartView.data = chartData
        chartView.isUserInteractionEnabled = false
        chartView.drawGridBackgroundEnabled = false
        chartView.drawBarShadowEnabled = true
        chartView.leftAxis.axisMaximum = availableStorage
        chartView.leftAxis.axisMinimum = 0.0
        chartView.leftAxis.enabled = false
        chartView.rightAxis.enabled = false
        chartView.xAxis.enabled = false
        chartView.extraBottomOffset = 10.0
        chartView.legend.font = chartView.legend.font.withSize(12.0)
        if #available(iOS 13.0, *) {
            chartView.legend.textColor = .label
        } else {
            chartView.legend.textColor = .black
        }
        chartView.legend.xEntrySpace = 15.0
        chartView.animate(yAxisDuration: 1.0)
    }
}

extension PreferencesView: PurchasesObserver {
    func updated(storageTier: StorageTier) {
        self.drawStorage(tier: storageTier)
    }
}
