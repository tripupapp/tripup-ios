//
//  AuthenticationView.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 18/05/2020.
//  Copyright © 2020 Vinoth Ramiah. All rights reserved.
//

import AuthenticationServices
import Foundation
import UIKit
import PhoneNumberKit

class AuthenticationView: UITableViewController {
    // Phone Number section
    @IBOutlet var phoneNumberField: PhoneNumberTextField!
    @IBOutlet var addPhoneNumberLabel: UILabel!
    @IBOutlet var nextPhoneNumberButton: UIButton!
    @IBOutlet var phoneNumberFieldActivity: UIActivityIndicatorView!
    @IBOutlet var phoneNumberVerificationField: UITextField!
    @IBOutlet var verifyPhoneNumberButton: UIButton!
    @IBOutlet var verifyPhoneNumberActivity: UIActivityIndicatorView!
    // Email section
    @IBOutlet var emailField: UITextField!
    @IBOutlet var addEmailLabel: UILabel!
    @IBOutlet var nextEmailButton: UIButton!
    @IBOutlet var emailFieldActivity: UIActivityIndicatorView!
    @IBOutlet var emailLinkActivity: UIActivityIndicatorView!
    // Sign in with Apple section
    @IBOutlet var appleButtonContainer: UIView!
    @IBOutlet var appleIDLabel: UILabel!
    @IBOutlet var appleUnlinkButton: UIButton!
    @IBOutlet var appleActivityView: UIActivityIndicatorView!

    private let log = Logger.self
    private let phoneNumberUtils = PhoneNumberService()
    private let emailUtils = EmailService()

    private var authenticationService: AuthenticationService!
    private var authInProgress: Any?
    private var api: LoginAPI?

    func initialise(authenticationService: AuthenticationService, api: LoginAPI?) {
        self.authenticationService = authenticationService
        self.api = api
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        if #available(iOS 13.0, *) {
            let appleButton = ASAuthorizationAppleIDButton(type: .continue, style: traitCollection.userInterfaceStyle == .light ? .white : .black)
            appleButton.cornerRadius = 0
            appleButton.addTarget(self, action: #selector(signInWithApple), for: .touchUpInside)
            appleButtonContainer.addSubview(appleButton)

            appleButton.translatesAutoresizingMaskIntoConstraints = false
            var constraints = [NSLayoutConstraint]()
            // Center button vertically in its container
            constraints.append(NSLayoutConstraint(
              item: appleButton,
              attribute: NSLayoutConstraint.Attribute.centerY,
              relatedBy: NSLayoutConstraint.Relation.equal,
              toItem: appleButtonContainer,
              attribute: NSLayoutConstraint.Attribute.centerY,
              multiplier: 1, constant: 0)
            )
            // Center button horizontally in its container
            constraints.append(NSLayoutConstraint(
              item: appleButton,
              attribute: NSLayoutConstraint.Attribute.centerX,
              relatedBy: NSLayoutConstraint.Relation.equal,
              toItem: appleButtonContainer,
              attribute: NSLayoutConstraint.Attribute.centerX,
              multiplier: 1, constant: 0)
            )
            // Button has equal height to its container
            constraints.append(NSLayoutConstraint(
              item: appleButton,
              attribute: NSLayoutConstraint.Attribute.height,
              relatedBy: NSLayoutConstraint.Relation.equal,
              toItem: appleButtonContainer,
              attribute: NSLayoutConstraint.Attribute.height,
              multiplier: 1, constant: 0)
            )
            // Button has equal width to its container
            constraints.append(NSLayoutConstraint(
              item: appleButton,
              attribute: NSLayoutConstraint.Attribute.width,
              relatedBy: NSLayoutConstraint.Relation.equal,
              toItem: appleButtonContainer,
              attribute: NSLayoutConstraint.Attribute.width,
              multiplier: 1, constant: 0)
            )
            appleButtonContainer.addConstraints(constraints)
        }

        phoneNumberField.toolbarPlaceholder = "Phone number"
        phoneNumberVerificationField.toolbarPlaceholder = "Verification code"
        emailField.toolbarPlaceholder = "Email address"
        phoneNumberField.keyboardToolbar.doneBarButton.setTarget(self, action: #selector(nextActionPhoneNumber))
        phoneNumberVerificationField.keyboardToolbar.doneBarButton.setTarget(self, action: #selector(verifyActionPhoneNumber))
        emailField.keyboardToolbar.doneBarButton.setTarget(self, action: #selector(nextActionEmail))

        // check for existing login progress
        if let loginProgressEncoded = UserDefaults.standard.data(forKey: UserDefaultsKey.LoginInProgress.rawValue) {
            if let loginPhoneNumber = try? JSONDecoder().decode(LoginPhoneNumber.self, from: loginProgressEncoded) {
                authInProgress = loginPhoneNumber
            } else if let email = String(data: loginProgressEncoded, encoding: .utf8) {
                authInProgress = email
            } else {
                fatalError("Invalid data stored in UserDefaults: \(UserDefaultsKey.LoginInProgress.rawValue)")
            }
        }
    }

    func handle(link emailVerificationLink: URL) -> Bool {
        guard authenticationService.isMagicSignInLink(emailVerificationLink) else { return false }
        guard let email = authInProgress as? String, emailUtils.isEmail(email) else { return false }
        authenticationService.link(email: email, verificationLink: emailVerificationLink, api: api) { [unowned self] success in
            if success {
                UserDefaults.standard.removeObject(forKey: UserDefaultsKey.LoginInProgress.rawValue)
                self.tableView.performBatchUpdates({
                    self.authInProgress = nil
                    self.tableView.reloadRows(at: [IndexPath(row: 0, section: 1)], with: .none)
                }, completion: nil)
            } else {
                UserDefaults.standard.removeObject(forKey: UserDefaultsKey.LoginInProgress.rawValue)
                self.view.makeToastie("There was an issue when verifying your email address. Please try again.", duration: 10.0, position: .top)
                self.tableView.performBatchUpdates({
                    self.authInProgress = nil
                }) { _ in
                    self.addEmailLabel.isHidden = true
                    self.emailField.enabled = true
                    self.emailField.text = email
                    self.emailField.isHidden = false
                    self.nextEmailButton.isHidden = false
                    self.nextEmailButton.setTitle("Next", for: .normal)
                }
            }
            self.emailLinkActivity.stopAnimating()
        }
        emailLinkActivity.startAnimating()
        return true
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch (indexPath.section, indexPath.row) {
        case (0, 0):
            if let number = authenticationService.authenticatedUser?.phoneNumber {
                addPhoneNumberLabel.isHidden = true
                phoneNumberField.isHidden = false
                phoneNumberField.text = number
                phoneNumberField.enabled = false
                nextPhoneNumberButton.isEnabled = true
                nextPhoneNumberButton.isHidden = false
                nextPhoneNumberButton.setTitle("Unlink", for: .normal)
            } else if let login = authInProgress as? LoginPhoneNumber {
                addPhoneNumberLabel.isHidden = true
                phoneNumberField.isHidden = false
                phoneNumberField.text = login.phoneNumber
                phoneNumberField.enabled = false
                nextPhoneNumberButton.isHidden = true
            } else {
                addPhoneNumberLabel.isHidden = false
                phoneNumberField.isHidden = true
                phoneNumberField.text = ""
                nextPhoneNumberButton.isHidden = true
            }
        case (1, 0):
            if let email = authenticationService.authenticatedUser?.email {
                addEmailLabel.isHidden = true
                emailField.isHidden = false
                emailField.text = email
                emailField.enabled = false
                nextEmailButton.isEnabled = true
                nextEmailButton.isHidden = false
                nextEmailButton.setTitle("Unlink", for: .normal)
            } else if let email = authInProgress as? String {
                addEmailLabel.isHidden = true
                emailField.isHidden = false
                emailField.text = email
                emailField.enabled = false
                nextEmailButton.isHidden = true
            } else {
                addEmailLabel.isHidden = false
                emailField.isHidden = true
                emailField.text = ""
                nextEmailButton.isHidden = true
            }
        case (2, 0):
            if let appleID = authenticationService.authenticatedUser?.appleID {
                appleButtonContainer.isHidden = true
                appleIDLabel.isHidden = false
                appleIDLabel.text = appleID
                appleUnlinkButton.isHidden = false
                appleUnlinkButton.addTarget(self, action: #selector(signInWithApple), for: .touchUpInside)
            } else {
                if #available(iOS 13.0, *) {
                    appleButtonContainer.isHidden = false
                    appleIDLabel.isHidden = true
                } else {
                    appleButtonContainer.isHidden = true
                    appleIDLabel.isHidden = false
                    appleIDLabel.text = "Not available on iOS 12"
                }
                appleUnlinkButton.isHidden = true
            }
        default:
            break
        }
        return super.tableView(tableView, cellForRowAt: indexPath)
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if indexPath.section == 0 && indexPath.row == 1 {
            if !(authInProgress is LoginPhoneNumber) {
                return 0
            }
        }
        if indexPath.section == 1 && indexPath.row == 1 {
            if !(authInProgress is String) {
                return 0
            }
        }
        return 44
    }

    override func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        if indexPath.section == 0, indexPath.row == 0, !addPhoneNumberLabel.isHidden {
            return indexPath
        }
        if indexPath.section == 1, indexPath.row == 0, !addEmailLabel.isHidden {
            return indexPath
        }
        return nil
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if indexPath.section == 0, indexPath.row == 0 {
            addPhoneNumber()
            tableView.deselectRow(at: indexPath, animated: false)
        }
        if indexPath.section == 1, indexPath.row == 0 {
            addEmail()
            tableView.deselectRow(at: indexPath, animated: false)
        }
    }

    private func addPhoneNumber() {
        addPhoneNumberLabel.isHidden = true
        phoneNumberField.enabled = true
        phoneNumberField.isHidden = false
        nextPhoneNumberButton.isHidden = false
        nextPhoneNumberButton.isEnabled = false
    }

    @IBAction func textFieldChanged(_ sender: UITextField) {
        switch (sender, sender.text) {
        case (phoneNumberField, .some(let text)) where phoneNumberUtils.isPhoneNumber(text):
            nextPhoneNumberButton.isEnabled = true
        case (phoneNumberVerificationField, .some(let code)) where code.count == authenticationService.phoneVerificationCodeLength:
            verifyPhoneNumberButton.isEnabled = true
        case (emailField, .some(let text)):
            let trimmedText = text.trimmingCharacters(in: .whitespaces)
            sender.text = trimmedText
            nextEmailButton.isEnabled = emailUtils.isEmail(trimmedText)
        default:
            nextPhoneNumberButton.isEnabled = false
            nextEmailButton.isEnabled = false
        }
    }

    @IBAction func nextActionPhoneNumber() {
        guard let text = phoneNumberField.text else { return }  // can reach here via keyboard toolbar button
        guard let authenticatedUser = authenticationService.authenticatedUser else {
            return
        }

        if authenticatedUser.phoneNumber == nil {
            guard let phoneNumber = phoneNumberUtils.phoneNumber(from: text) else { return }
            phoneNumberField.text = phoneNumber
            phoneNumberField.enabled = false
            authenticationService.login(withNumber: phoneNumber) { [unowned self] state in
                if case LoginState.pendingNumberVerification(let phoneNumber, let verificationID) = state {
                    let loginPhoneNumber = LoginPhoneNumber(phoneNumber: phoneNumber, verificationID: verificationID)
                    let loginPhoneNumberEncoded = try! JSONEncoder().encode(loginPhoneNumber)
                    UserDefaults.standard.set(loginPhoneNumberEncoded, forKey: UserDefaultsKey.LoginInProgress.rawValue)
                    self.tableView.performBatchUpdates({
                        self.authInProgress = loginPhoneNumber
                    }, completion: nil)
                } else if case LoginState.failed(.phoneNumberError) = state {
                    self.phoneNumberField.enabled = true
                    self.nextPhoneNumberButton.isHidden = false
                    self.view.makeToastie("There was an issue when validating your phone number. Please try again.", duration: 10.0, position: .top)
                } else {
                    preconditionFailure()
                }
                self.phoneNumberFieldActivity.stopAnimating()
            }
            phoneNumberFieldActivity.startAnimating()
            nextPhoneNumberButton.isHidden = true

        } else {
            guard authenticatedUser.email != nil || authenticatedUser.appleID != nil else {
                self.view.superview?.makeToastie("Must have at least one login registered. Please register an alternate login before trying to unlink.", duration: 10.0)
                return
            }
            let alert = UIAlertController(title: "Are you sure you want to unlink this phone number from your account?", message: "Contacts will no longer be able to add you on TripUp with this phone number", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Yes", style: .default) { _ in
                self.phoneNumberFieldActivity.startAnimating()
                self.nextPhoneNumberButton.isHidden = true
                self.authenticationService.unlinkNumber(api: self.api) { [unowned self] success in
                    if success {
                        self.tableView.performBatchUpdates({
                            self.tableView.reloadRows(at: [IndexPath(row: 0, section: 0)], with: .none)
                        }, completion: nil)
                    } else {
                        self.view.makeToastie("There was an issue with unlinking your phone number. Please try again.", duration: 10.0, position: .top)
                        self.nextPhoneNumberButton.isHidden = false
                    }
                    self.phoneNumberFieldActivity.stopAnimating()
                }
            })
            alert.addAction(UIAlertAction(title: "No", style: .cancel, handler: nil))
            present(alert, animated: true, completion: nil)
        }
    }

    @IBAction func verifyActionPhoneNumber() {
        guard let verificationCode = phoneNumberVerificationField.text else { return }    // can reach here via keyboard toolbar button
        guard verificationCode.count == authenticationService.phoneVerificationCodeLength else { return }
        guard let loginPhoneNumber = authInProgress as? LoginPhoneNumber else { return }
        phoneNumberVerificationField.enabled = false

        authenticationService.linkNumber(id: loginPhoneNumber.verificationID, verificationCode: verificationCode, api: api) { [unowned self] success in
            if success {
                UserDefaults.standard.removeObject(forKey: UserDefaultsKey.LoginInProgress.rawValue)
                self.tableView.performBatchUpdates({
                    self.authInProgress = nil
                    self.tableView.reloadRows(at: [IndexPath(row: 0, section: 0)], with: .none)
                }, completion: nil)
            } else {
                UserDefaults.standard.removeObject(forKey: UserDefaultsKey.LoginInProgress.rawValue)
                self.view.makeToastie("There was an issue when validating your authentication code. Please try again.", duration: 10.0, position: .top)
                self.tableView.performBatchUpdates({
                    self.authInProgress = nil
                }) { _ in
                    self.addPhoneNumberLabel.isHidden = true
                    self.phoneNumberField.enabled = true
                    self.phoneNumberField.isHidden = false
                    self.nextPhoneNumberButton.isHidden = false
                    self.nextPhoneNumberButton.setTitle("Next", for: .normal)
                }
            }
            self.verifyPhoneNumberActivity.stopAnimating()
            self.verifyPhoneNumberButton.isHidden = false
        }
        verifyPhoneNumberActivity.startAnimating()
        verifyPhoneNumberButton.isHidden = true
    }

    private func addEmail() {
        emailField.enabled = true
        emailField.isHidden = false
        nextEmailButton.isHidden = false
        nextEmailButton.isEnabled = false
        addEmailLabel.isHidden = true
    }

    @IBAction func nextActionEmail() {
        guard let authenticatedUser = authenticationService.authenticatedUser else {
            return
        }
        if authenticatedUser.email == nil {
            guard let email = emailField.text, emailUtils.isEmail(email) else { return }  // can reach here via keyboard toolbar button
            emailField.enabled = false
            authenticationService.login(withEmail: email) { [unowned self] state in
                if case LoginState.pendingEmailVerification(let email) = state {
                    UserDefaults.standard.set(email.data(using: .utf8)!, forKey: UserDefaultsKey.LoginInProgress.rawValue)
                    self.tableView.performBatchUpdates({
                        self.authInProgress = email
                    }, completion: nil)
                } else if case LoginState.failed(.emailError) = state {
                    self.emailField.enabled = true
                    self.nextEmailButton.isHidden = false
                    self.view.makeToastie("There was an issue when validating your email address. Please try again.", duration: 10.0, position: .top)
                } else {
                    preconditionFailure()
                }
                self.emailFieldActivity.stopAnimating()
            }
            emailFieldActivity.startAnimating()
            nextEmailButton.isHidden = true

        } else {
            guard authenticatedUser.phoneNumber != nil || authenticatedUser.appleID != nil else {
                self.view.superview?.makeToastie("Must have at least one login registered. Please register an alternate login before trying to unlink.", duration: 10.0)
                return
            }
            let alert = UIAlertController(title: "Are you sure you want to unlink this email address from your account?", message: "Contacts will no longer be able to add you on TripUp with this email", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Yes", style: .default) { _ in
                self.emailFieldActivity.startAnimating()
                self.nextEmailButton.isHidden = true
                self.authenticationService.unlinkEmail(api: self.api) { [unowned self] success in
                    if success {
                        self.tableView.performBatchUpdates({
                            self.tableView.reloadRows(at: [IndexPath(row: 0, section: 1)], with: .none)
                        }, completion: nil)
                    } else {
                        self.view.makeToastie("There was an issue with unlinking your email. Please try again.", duration: 10.0, position: .top)
                        self.nextEmailButton.isHidden = false
                    }
                    self.emailFieldActivity.stopAnimating()
                }
            })
            alert.addAction(UIAlertAction(title: "No", style: .cancel, handler: nil))
            present(alert, animated: true, completion: nil)
        }
    }

    @IBAction func resetEmailAction() {
        UserDefaults.standard.removeObject(forKey: UserDefaultsKey.LoginInProgress.rawValue)
        tableView.performBatchUpdates({
            authInProgress = nil
            tableView.reloadRows(at: [IndexPath(row: 0, section: 1)], with: .none)
        }, completion: nil)
    }

    @IBAction func signInWithApple() {
        guard let authenticatedUser = authenticationService.authenticatedUser else {
            return
        }
        if authenticatedUser.appleID == nil {
            guard #available(iOS 13.0, *) else { preconditionFailure() }
            authenticationService.linkApple(api: api, presentingController: self) { [unowned self] success in
                if success {
                    self.tableView.reloadRows(at: [IndexPath(row: 0, section: 2)], with: .none)
                } else {
                    self.view.makeToastie("There was an issue signing in with Apple. Please try again.", duration: 10.0, position: .top)
                }
                self.appleActivityView.stopAnimating()
            }
            self.appleActivityView.startAnimating()
        } else {
            guard authenticatedUser.phoneNumber != nil || authenticatedUser.email != nil else {
                self.view.superview?.makeToastie("Must have at least one login registered. Please register an alternate login before trying to unlink.", duration: 10.0)
                return
            }
            let alert = UIAlertController(title: "Are you sure you want to unlink Sign in with Apple from your account?", message: "Contacts will no longer be able to add you on TripUp with this email", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Yes", style: .default) { [unowned self] _ in
                self.appleActivityView.startAnimating()
                self.appleUnlinkButton.isHidden = true
                self.authenticationService.unlinkApple(api: self.api) { [unowned self] success in
                    if success {
                        self.tableView.reloadRows(at: [IndexPath(row: 0, section: 2)], with: .none)
                    } else {
                        self.view.makeToastie("There was an issue unlinking your account from Apple. Please try again.", duration: 10.0, position: .top)
                        self.appleUnlinkButton.isHidden = false
                    }
                    self.appleActivityView.stopAnimating()
                }
            })
            alert.addAction(UIAlertAction(title: "No", style: .cancel, handler: nil))
            present(alert, animated: true, completion: nil)
        }
    }
}

extension AuthenticationView: UITextFieldDelegate {
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        guard let text = textField.text else { return true }
        switch textField {
        case phoneNumberVerificationField:
            let newLength = text.count + string.count - range.length
            return newLength <= authenticationService.phoneVerificationCodeLength
        default:
            return true
        }
    }
}

@available(iOS 13.0, *)
extension AuthenticationView: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        return view.window!
    }
}

fileprivate extension UIControl {
    var enabled: Bool {
        get {
            return isEnabled
        }
        set {
            isEnabled = newValue
            alpha = newValue ? 1 : 0.5
        }
    }
}
