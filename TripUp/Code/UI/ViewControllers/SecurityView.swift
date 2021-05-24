//
//  SecurityView.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 04/02/2020.
//  Copyright © 2020 Vinoth Ramiah. All rights reserved.
//

import Foundation
import LocalAuthentication
import MobileCoreServices
import UIKit

class SecurityView: UIViewController, UIViewControllerTransparent {
    @IBOutlet var headerView: UIView!
    @IBOutlet var securityMessageFail: UILabel!
    @IBOutlet var securityContents: UIScrollView!
    @IBOutlet var primaryLabels: [UILabel]!
    @IBOutlet var secondaryLabels: [UILabel]!
    @IBOutlet var keyImage: UIImageView!
    @IBOutlet var userKeyPassword: UILabel!
    @IBOutlet var iCloudKeychainBox: UIView!
    @IBOutlet var iCloudKeychainSwitch: UISwitch!
    @IBOutlet var nextButton: UIButton!

    var transparent: Bool = false
    var navigationBarHidden = false
    var nextAction: Closure?

    private let log = Logger.self
    private let localAuthContext = LAContext()
    private var keychain: Keychain<CryptoPublicKey, CryptoPrivateKey>!
    private var primaryUser: User!

    func initialise(primaryUser: User, keychain: Keychain<CryptoPublicKey, CryptoPrivateKey>) {
        self.primaryUser = primaryUser
        self.keychain = keychain
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        headerView.backgroundColor = .clear
        securityContents.isHidden = true
        securityMessageFail.isHidden = true
        if #available(iOS 14.0, *), let image = UIImage(systemName: "key") {
            keyImage.image = image
        }
        if !transparent, #available(iOS 13.0, *) {
            iCloudKeychainBox.backgroundColor = UIColor.label.withAlphaComponent(0.15)
        } else {
            iCloudKeychainBox.backgroundColor = UIColor.black.withAlphaComponent(0.15)
        }
        iCloudKeychainBox.layer.cornerRadius = 5.0
        nextButton.layer.cornerRadius = 5.0

        if transparent {    // transparent is set to true when loading the view during login procedure
            view.backgroundColor = .clear
            securityContents.indicatorStyle = .white
            primaryLabels.forEach{ $0.textColor = .white }
            secondaryLabels.forEach{ $0.textColor = .white }
            securitySettings(visible: true)
        } else {
            headerView.removeFromSuperview()
            nextButton.removeFromSuperview()
            var error: NSError?
            if localAuthContext.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
                let touchIDReason = "Gain access to security settings"  // faceid gets its description only on first attempt, and from info.plist usage description
                localAuthContext.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: touchIDReason) { success, error in
                    switch (success, error) {
                    case (true, _):
                        DispatchQueue.main.async {
                            self.securitySettings(visible: true)
                        }
                    case (false, .some(let error as LAError)) where error.code == .biometryNotAvailable || error.code == .biometryNotEnrolled:
                        DispatchQueue.main.async {
                            self.securitySettings(visible: true)
                        }
                    case (false, _):
                        self.log.error("\(String(describing: error))")
                        DispatchQueue.main.async {
                            self.securitySettings(visible: false)
                        }
                    }
                }
            } else {
                log.warning(error?.localizedDescription ?? "Can't evaluate policy")
                securitySettings(visible: true)
            }
        }

        #if DEBUG
        let screenshotEnv = ProcessInfo.processInfo.environment["UITest-Screenshots"] != nil
        iCloudKeychainSwitch.setOn(primaryUserPassOniCloud || screenshotEnv, animated: false)
        #else
        iCloudKeychainSwitch.setOn(primaryUserPassOniCloud, animated: false)
        #endif
        if #available(iOS 13.0, *) {
            userKeyPassword.font = UIFont.monospacedSystemFont(ofSize: 35.0, weight: .regular)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        securityContents.flashScrollIndicators()
    }

    private func securitySettings(visible: Bool) {
        if visible {
            userKeyPassword.text = primaryUserPass
            securityContents.isHidden = false
            securityMessageFail.isHidden = true
        } else {
            securityContents.isHidden = true
            securityMessageFail.text = "🚫 \(localAuthContext.biometryType == .faceID ? "FaceID" : "TouchID") verification failed. Please try again"
            securityMessageFail.isHidden = false
        }
    }

    @IBAction func toggleiCloudKeychainSave(_ sender: UISwitch) {
        if sender.isOn {
            savePrimaryUserPassToiCloud()
        } else {
            removePrimaryUserPassFromiCloud()
        }
    }

    @IBAction func tapOnPassword(_ sender: UILongPressGestureRecognizer) {
        guard let userKeyPassLabel = sender.view as? UILabel else { return }
        switch sender.state {
        case .possible:
            break
        case .began, .changed:
            userKeyPassLabel.isHighlighted = true
        case .ended, .cancelled, .failed:
            userKeyPassLabel.isHighlighted = false
        @unknown default:
            preconditionFailure("Unimplemented case \(sender.state)")
        }
        guard sender.state == .ended else { return }

        let expirationDate = Date(timeIntervalSinceNow: TimeInterval(30))   // 30 seconds before password is cleared from clipboard
        UIPasteboard.general.setItems([[kUTTypeUTF8PlainText as String: userKeyPassLabel.text!]], options: [UIPasteboard.OptionsKey.expirationDate: expirationDate])

        self.view.makeToastie("Copied to clipboard", duration: 3.0, position: .bottom)
    }

    @IBAction func nextButton(_ sender: UIButton) {
        if iCloudKeychainSwitch.isOn && !primaryUserPassOniCloud {
            savePrimaryUserPassToiCloud()
        } else if !iCloudKeychainSwitch.isOn && primaryUserPassOniCloud {
            removePrimaryUserPassFromiCloud()
        }
        nextAction?()
    }
}

extension SecurityView {
    private var primaryUserPass: String {
        return try! keychain.retrievePrivateKey(withFingerprint: primaryUser.fingerprint, keyType: .user)!.password!
    }

    private var primaryUserPassOniCloud: Bool {
        return try! keychain.retrieveFromiCloud(lookupKey: primaryUser.uuid.string) != nil
    }

    private func savePrimaryUserPassToiCloud() {
        try! keychain.saveToiCloud(primaryUserPass, lookupKey: primaryUser.uuid.string)
    }

    private func removePrimaryUserPassFromiCloud() {
        keychain.clearFromiCloud(lookupKey: primaryUser.uuid.string)
    }
}
