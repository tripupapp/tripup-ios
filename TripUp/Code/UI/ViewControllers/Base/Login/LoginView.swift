//
//  LoginScreen.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 05/06/2017.
//  Copyright © 2017 Vinoth Ramiah. All rights reserved.
//

import AuthenticationServices
import Foundation
import UIKit

import TripUpViews

class LoginView: UIViewController, UIViewControllerTransparent {
    enum LoginRenderState {
        case phoneNumberInitial
        case phoneNumberVerification
        case emailInitial
        case emailVerification
        case ssoInitial
    }

    @IBOutlet var signInOptions: UIStackView!
    @IBOutlet var phoneEmailButton: UIButton!
    @IBOutlet var ssoBackButton: UIButton!

    @IBOutlet var phoneEmailViews: [UIView]!
    @IBOutlet var fields_stackview: UIStackView!
    @IBOutlet var segmentControl: UISegmentedControl!
    @IBOutlet var phoneNumberField: UITextFieldPhoneNumber!
    @IBOutlet var verification_field: UITextField2!
    @IBOutlet var emailAddressField: UITextField2!
    @IBOutlet var magicLinkLabel: UILabel!

    @IBOutlet var login_button: UIButton!
    @IBOutlet var activity_view: UIActivityIndicatorView!
    @IBOutlet var logoItems: [UIView]!
    @IBOutlet var helpButton: UIButton!
    @IBOutlet var policyButtons: [UIButton]!
    @IBOutlet var loginButtonSpaceFromStack: NSLayoutConstraint!

    weak var appDelegateExtension: AppDelegateExtension?
    var transparent: Bool = true
    var navigationBarHidden: Bool = true
    var logicController: LoginLogicController!

    private let log_ = Logger.self
    private let verificationCodeLength_ = 6
    private var logoAnimation: UIViewPropertyAnimator?
    private var emailVerification: Closure?
    private let phoneNumberUtils: PhoneNumberUtils = PhoneNumberService()
    private let emailUtils: EmailUtils = EmailService()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        if #available(iOS 13.0, *) {
            helpButton.setTitle(nil, for: .normal)
            helpButton.setImage(UIImage(systemName: "questionmark.circle"), for: .normal)

            let authorizationButton = ASAuthorizationAppleIDButton(type: .default, style: .white)
            authorizationButton.addTarget(self, action: #selector(authenticateWithAppleID), for: .touchUpInside)
            signInOptions.addArrangedSubview(authorizationButton)

            phoneEmailButton.layer.cornerRadius = authorizationButton.cornerRadius
            phoneEmailButton.layer.borderWidth = 1.0
            phoneEmailButton.layer.borderColor = UIColor.init(white: 0, alpha: 0.25).cgColor
        } else {
            signInOptions.isHidden = true
            phoneEmailViews.forEach{ $0.isHidden = false }
        }

        let segmentTitleAttributes = [
            NSAttributedString.Key.foregroundColor: UIColor.white,
            NSAttributedString.Key.font: UIFont.systemFont(ofSize: 19.0, weight: .regular)
        ]
        segmentControl.setTitleTextAttributes(segmentTitleAttributes, for: .normal)
        segmentControl.setTitleTextAttributes(segmentTitleAttributes, for: .selected)

        // check for existing login progress
        if let loginProgressEncoded = UserDefaults.standard.data(forKey: UserDefaultsKey.LoginInProgress.rawValue) {
            let decoder = JSONDecoder()
            if let loginPhoneNumber = try? decoder.decode(LoginPhoneNumber.self, from: loginProgressEncoded) {
                phoneNumberField.text = loginPhoneNumber.phoneNumber
                renderStackView(.phoneNumberVerification, setResponder: false, animate: false)
            } else if let email = String(data: loginProgressEncoded, encoding: .utf8) {
                emailAddressField.text = email
                renderStackView(.emailVerification, setResponder: false, animate: false)
            } else {
                fatalError("Invalid data stored in UserDefaults.\(UserDefaultsKey.LoginInProgress.rawValue)")
            }
        } else {
            renderStackView(.phoneNumberInitial, setResponder: false, animate: false)
        }

        // hide items
        logoItems.forEach{ $0.alpha = 0 }
        segmentControl.alpha = 0
        fields_stackview.alpha = 0
        login_button.alpha = 0
        helpButton.alpha = 0
        signInOptions.alpha = 0
        policyButtons.forEach{ $0.alpha = 0 }

        phoneNumberField.toolbarPlaceholder = "Phone number"
        verification_field.toolbarPlaceholder = "Verification code"
        emailAddressField.toolbarPlaceholder = "Email address"
        phoneNumberField.keyboardToolbar.doneBarButton.setTarget(self, action: #selector(authenticate))
        verification_field.keyboardToolbar.doneBarButton.setTarget(self, action: #selector(authenticate))
        emailAddressField.keyboardToolbar.doneBarButton.setTarget(self, action: #selector(authenticate))
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        Keyboard.shared.adjustKeyboardDistance(by: loginButtonSpaceFromStack.constant + login_button.frame.height)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        logoAnimation = UIViewPropertyAnimator(duration: 3.0, curve: .easeIn) { [unowned self] in
            self.logoItems.forEach{ $0.alpha = 1 }
        }
        logoAnimation?.addCompletion { [unowned self] _ in
            let finalAnimations = UIViewPropertyAnimator(duration: 3.0, curve: .easeInOut) {
                self.segmentControl.alpha = 1
                self.fields_stackview.alpha = 1
                self.signInOptions.alpha = 1.0
                self.policyButtons.forEach{ $0.alpha = 0.5 }
                self.login_button.alpha = self.login_button.isEnabled ? 1.0 : 0.5
                self.helpButton.alpha = 1
            }
            precondition(Thread.isMainThread)
            if let emailVerification = self.emailVerification {
                finalAnimations.addCompletion { _ in
                    precondition(Thread.isMainThread)
                    emailVerification()
                    self.emailVerification = nil
                }
            }
            finalAnimations.startAnimation()
        }
        logoAnimation?.startAnimation()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        Keyboard.shared.adjustKeyboardDistance(by: -(loginButtonSpaceFromStack.constant + login_button.frame.height))
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        super.prepare(for: segue, sender: sender)

        switch segue.destination {
        case let policy as PolicyView:
            if segue.identifier == "privacy" {
                policy.initialise(title: "Privacy Policy", url: Globals.Directories.legal.appendingPathComponent(Globals.Documents.privacyPolicy.renderedFilename, isDirectory: false))
            } else if segue.identifier == "eula" {
                let url = Bundle.main.url(forResource: "eula", withExtension: "html")!
                policy.initialise(title: "EULA", url: url)
            }
        default:
            break
        }
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }

    @IBAction func togglePhoneEmailViews(_ sender: UIButton) {
        ssoBackButton.isHidden.toggle()
        signInOptions.isHidden.toggle()
        phoneEmailViews.forEach{ $0.isHidden.toggle() }
    }

    @IBAction func UITextFieldChanged(_ sender: UITextField) {
        switch (sender, sender.text) {
        case (phoneNumberField, .some(let text)) where phoneNumberUtils.isPhoneNumber(text):
            login_button.enabled = true
        case (emailAddressField, .some(let text)):
            let trimmedText = text.trimmingCharacters(in: .whitespaces)
            sender.text = trimmedText
            login_button.enabled = emailUtils.isEmail(trimmedText)
        case (verification_field, .some(let code)) where code.count == verificationCodeLength_:
            login_button.enabled = true
        default:
            login_button.enabled = false
        }
    }

    private func handle(_ state: LoginState) {
        switch state {
        case .failed(.phoneNumberError):
            renderStackView(.phoneNumberInitial, setResponder: true, animate: true)
            self.view.window?.makeToastie("There was an issue when validating your phone number. Please try again.", duration: 10.0, position: .top)

        case .failed(.emailError):
            renderStackView(.emailInitial, setResponder: true, animate: true)
            self.view.window?.makeToastie("There was an issue when validating your email address. Please try again.", duration: 10.0, position: .top)

        case .failed(.appleError):
            renderStackView(.ssoInitial, setResponder: false, animate: true)
            view.makeToastie("There was an issue initiating Sign in with Apple. Please try again.", duration: 10.0, position: .top)

        case .pendingNumberVerification(let phoneNumber, let verificationID):
            let loginPhoneNumber = LoginPhoneNumber(phoneNumber: phoneNumber, verificationID: verificationID)
            let encoder = JSONEncoder()
            let loginPhoneNumberEncoded = try! encoder.encode(loginPhoneNumber)
            UserDefaults.standard.set(loginPhoneNumberEncoded, forKey: UserDefaultsKey.LoginInProgress.rawValue)
            renderStackView(.phoneNumberVerification, setResponder: true, animate: true)

        case .failed(.verificationCodeError):
            reset(to: .phoneNumberInitial)
            self.view.window?.makeToastie("There was an issue when validating your authentication code. Please try again.", duration: 10.0, position: .top)

        case .pendingEmailVerification(let email):
            UserDefaults.standard.set(email.data(using: .utf8)!, forKey: UserDefaultsKey.LoginInProgress.rawValue)
            renderStackView(.emailVerification, setResponder: true, animate: true)

        case .failed(.emailVerificationError):
            reset(to: .emailInitial)
            self.view.window?.makeToastie("There was an issue when verifying your email address. Please try again.", duration: 10.0, position: .top)

        case .authenticated(let authenticatedUser):
            appDelegateExtension?.userCredentials(from: authenticatedUser) { [weak self] state in
                self?.handle(state)
            }

        case .passwordRequired(let callback):
            requestPassword(attemptNo: 1, callback: callback)

        case .loggedIn:
            UserDefaults.standard.removeObject(forKey: UserDefaultsKey.LoginInProgress.rawValue)
            appDelegateExtension?.presentNextRootViewController(after: self)

        case .failed(.apiError):
            if !signInOptions.isHidden {
                reset(to: .ssoInitial)
            } else if segmentControl.selectedSegmentIndex == 0 {
                reset(to: .phoneNumberInitial)
            } else {
                reset(to: .emailInitial)
            }
            self.view.window?.makeToastie("There was an error communicating with the server. Please try again later.", duration: 10.0, position: .top)
        }
    }

    private func requestPassword(attemptNo: Int, callback: @escaping (String) -> Bool) {
        assert(attemptNo > 0 && attemptNo <= 3)
        let alertController = UIAlertController(title: "Password Required", message: attemptNo == 1 ? nil : "Invalid password supplied. Try again", preferredStyle: .alert)
        alertController.addTextField { textField in
            textField.isSecureTextEntry = true
        }
        let unlockAction = UIAlertAction(title: "Unlock", style: .default) { [unowned alertController] _ in
            guard let password = alertController.textFields![0].text else { self.requestPassword(attemptNo: attemptNo + 1, callback: callback); return }
            if callback(password) {
                self.handle(.loggedIn)
            } else if attemptNo < 3 {
                self.requestPassword(attemptNo: attemptNo + 1, callback: callback)
            } else {
                if !self.signInOptions.isHidden {
                    self.reset(to: .ssoInitial)
                } else if self.segmentControl.selectedSegmentIndex == 0 {
                    self.reset(to: .phoneNumberInitial)
                } else {
                    self.reset(to: .emailInitial)
                }
                self.view.window?.makeToastie("Invalid password, please try again or contact support by tapping the '?' icon.", duration: 5.0, position: .top)
            }
        }
        alertController.addAction(unlockAction)
        present(alertController, animated: true)
    }

    @IBAction func authenticate() {
        switch (segmentControl.selectedSegmentIndex, UserDefaults.standard.data(forKey: UserDefaultsKey.LoginInProgress.rawValue)) {
        case (0, .none):
            guard let text = phoneNumberField.text else { return }  // can reach here via "Done" keyboard toolbar button or return key
            guard let phoneNumber = phoneNumberUtils.phoneNumber(from: text) else { return }

            phoneNumberField.text = phoneNumber
            logicController.login(withNumber: phoneNumber) { [unowned self] state in
                self.handle(state)
                self.activity_view.stopAnimating()
            }

            phoneNumberField.resignFirstResponder()
            phoneNumberField.enabled = false

        case (0, .some(let data)):
            guard let verificationCode = verification_field.text else { return }    // can reach here via "Done" keyboard toolbar button or return key
            guard verificationCode.count == verificationCodeLength_ else { return }

            let loginPhoneNumber = try! JSONDecoder().decode(LoginPhoneNumber.self, from: data)
            logicController.verifyNumber(id: loginPhoneNumber.verificationID, withCode: verificationCode) { [unowned self] state in
                self.handle(state)
            }

            verification_field.resignFirstResponder()
            verification_field.enabled = false

        case (1, .none):
            guard let text = emailAddressField.text else { return }  // can reach here via "Done" keyboard toolbar button or return key
            guard emailUtils.isEmail(text) else { return }

            logicController.login(withEmail: text) { [unowned self] state in
                self.handle(state)
                self.activity_view.stopAnimating()
            }

            emailAddressField.resignFirstResponder()
            emailAddressField.enabled = false

        case (1, .some(let data)) where String(data: data, encoding: .utf8) != nil:
            reset(to: .emailInitial)
            return

        default:
            break
        }

        segmentControl.isEnabled = false
        login_button.enabled = false
        activity_view.startAnimating()
    }

    @available(iOS 13, *)
    @IBAction func authenticateWithAppleID() {
        logicController.loginWithApple(presentingController: self) { [unowned self] state in
            self.handle(state)
        }
        activity_view.startAnimating()
    }

    func handle(link emailVerificationLink: URL) -> Bool {
        guard logicController.isMagicSignInLink(emailVerificationLink) else {
            return false
        }
        guard let loginProgressEncoded = UserDefaults.standard.data(forKey: UserDefaultsKey.LoginInProgress.rawValue), let email = String(data: loginProgressEncoded, encoding: .utf8) else {
            return false
        }
        let closure = { [weak self] in
            self?.logicController.verify(email: email, withLink: emailVerificationLink) { [weak self] state in
                self?.handle(state)
            }

            self?.login_button.enabled = false
            self?.activity_view.startAnimating()
        }
        if let logoAnimation = logoAnimation, !logoAnimation.isRunning {
            closure()
        } else {
            precondition(Thread.isMainThread)
            emailVerification = closure
        }
        return true
    }

    @IBAction func switchLoginMethod(_ sender: UISegmentedControl) {
        if sender.selectedSegmentIndex == 0 {
            renderStackView(.phoneNumberInitial, setResponder: emailAddressField.isFirstResponder, animate: true)
        } else {
            renderStackView(.emailInitial, setResponder: phoneNumberField.isFirstResponder, animate: true)
        }
    }

    private func reset(to loginState: LoginRenderState) {
        UserDefaults.standard.removeObject(forKey: UserDefaultsKey.LoginInProgress.rawValue)
        renderStackView(loginState, setResponder: true, animate: true)
        activity_view.stopAnimating()
    }
}

extension LoginView {
    private func renderStackView(_ loginState: LoginRenderState, setResponder becomeFirstResponder: Bool, animate: Bool) {
        switch loginState {
        case .phoneNumberInitial:
            segmentControl.isEnabled = true
            segmentControl.selectedSegmentIndex = 0
            phoneNumberField.enabled = true
            verification_field.enabled = false
            verification_field.text = nil
            emailAddressField.enabled = false

            let fieldVisibility = {
                self.phoneNumberField.isHiddenInStackView = false
                self.verification_field.isHiddenInStackView = true
                self.emailAddressField.isHiddenInStackView = true
                self.magicLinkLabel.isHiddenInStackView = true
                self.fields_stackview.layoutIfNeeded()
                if becomeFirstResponder {
                    self.phoneNumberField.becomeFirstResponder()
                }
            }
            if animate {
                UIView.animate(withDuration: 0.3) {
                    fieldVisibility()
                }
            } else {
                fieldVisibility()
            }
            login_button.setTitle("LOGIN", for: .normal)
            if let text = phoneNumberField.text {
                login_button.enabled = phoneNumberUtils.isPhoneNumber(text)
            } else {
                login_button.enabled = false
            }

        case .phoneNumberVerification:
            segmentControl.isEnabled = false
            segmentControl.selectedSegmentIndex = 0
            phoneNumberField.enabled = false
            verification_field.enabled = true
            verification_field.text = nil
            emailAddressField.enabled = false

            let fieldVisibility = {
                self.phoneNumberField.isHiddenInStackView = false
                self.verification_field.isHiddenInStackView = false
                self.emailAddressField.isHiddenInStackView = true
                self.magicLinkLabel.isHiddenInStackView = true
                self.fields_stackview.layoutIfNeeded()
                if becomeFirstResponder {
                    self.verification_field.becomeFirstResponder()
                }
            }
            if animate {
                UIView.animate(withDuration: 0.3) {
                    fieldVisibility()
                }
            } else {
                fieldVisibility()
            }
            login_button.setTitle("VERIFY", for: .normal)
            login_button.enabled = false

        case .emailInitial:
            segmentControl.isEnabled = true
            segmentControl.selectedSegmentIndex = 1
            phoneNumberField.enabled = false
            verification_field.enabled = false
            verification_field.text = nil
            emailAddressField.enabled = true

            let fieldVisibility = {
                self.phoneNumberField.isHiddenInStackView = true
                self.verification_field.isHiddenInStackView = true
                self.emailAddressField.isHiddenInStackView = false
                self.magicLinkLabel.isHiddenInStackView = true
                self.fields_stackview.layoutIfNeeded()
                if becomeFirstResponder {
                    self.emailAddressField.becomeFirstResponder()
                }
            }
            if animate {
                UIView.animate(withDuration: 0.3) {
                    fieldVisibility()
                }
            } else {
                fieldVisibility()
            }
            login_button.setTitle("LOGIN", for: .normal)
            if let text = emailAddressField.text {
                login_button.enabled = emailUtils.isEmail(text)
            } else {
                login_button.enabled = false
            }

        case .emailVerification:
            segmentControl.isEnabled = false
            segmentControl.selectedSegmentIndex = 1
            phoneNumberField.enabled = false
            verification_field.enabled = false
            verification_field.text = nil
            emailAddressField.enabled = false

            let fieldVisibility = {
                self.phoneNumberField.isHiddenInStackView = true
                self.verification_field.isHiddenInStackView = true
                self.emailAddressField.isHiddenInStackView = false
                self.magicLinkLabel.isHiddenInStackView = false
                self.fields_stackview.layoutIfNeeded()
            }
            if animate {
                UIView.animate(withDuration: 0.3) {
                    fieldVisibility()
                }
            } else {
                fieldVisibility()
            }
            login_button.setTitle("RESET", for: .normal)
            login_button.enabled = true

        case .ssoInitial:
            activity_view.stopAnimating()
        }
    }
}

extension LoginView: UITextFieldDelegate {
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        guard let text = textField.text else { return true }
        switch textField {
        case verification_field:
            let newLength = text.count + string.count - range.length
            return newLength <= verificationCodeLength_
        default:
            return true
        }
    }
}

@available(iOS 13.0, *)
extension LoginView: ASAuthorizationControllerPresentationContextProviding {
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
