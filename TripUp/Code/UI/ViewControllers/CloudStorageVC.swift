//
//  CloudStorageVC.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 09/09/2020.
//  Copyright © 2020 Vinoth Ramiah. All rights reserved.
//

import Foundation
import UIKit

import AnimatedGradientView

class CloudStorageVC: UIViewController, UIViewControllerTransparent, UIViewControllerAnimatedGradient {
    @IBOutlet var labels: [UILabel]!
    @IBOutlet var headerLabel: UILabel!
    @IBOutlet var entitlementInfo: UILabel!
    @IBOutlet var stackView: UIStackView!
    @IBOutlet var freeButton: UIButton!
    @IBOutlet var closeButton: UIButton!
    @IBOutlet var activityIndicator: UIActivityIndicatorView!

    var transparent: Bool = true
    var navigationBarHidden: Bool = true
    var showFreeButton: Bool = true
    var isModal: Bool = true
    var endClosure: Closure?

    var animatedGradient: AnimatedGradientView?
    var animatedGradientEnterForegroundToken: NSObjectProtocol?
    var animatedGradientEnterBackgroundToken: NSObjectProtocol?

    private var purchasesController: PurchasesController?
    private var availableParcels: [PurchasesController.Parcel]?
    private var selectedButton: UIButton? {
        didSet {
            selectedButton?.drawBorder(true)
        }
    }

    func initialise(purchasesController: PurchasesController) {
        self.purchasesController = purchasesController
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        if !(navigationController is UIViewControllerAnimatedGradient) {
            setupAnimatedGradient()
        }

        if transparent {
            view.backgroundColor = .clear
            labels.forEach{ $0.textColor = .white }
        }

        if #available(iOS 13.0, *) {
            activityIndicator.style = .large
        } else {
            activityIndicator.style = transparent ? .whiteLarge : .gray
        }

        stackView.arrangedSubviews.forEach({ $0.removeFromSuperview() })
        stackView.isHidden = true
        freeButton.layer.cornerRadius = 7.5
        freeButton.isHidden = true
        closeButton.isHidden = !isModal
        labels.forEach{ $0.isHidden = true }
        activityIndicator.startAnimating()

        guard let purchasesController = purchasesController else {
            loadPurchasesFailed()
            return
        }

        purchasesController.offers { [weak self, weak purchasesController] parcels in
            guard let self = self else {
                return
            }
            guard let parcels = parcels, let purchasesController = purchasesController else {
                self.loadPurchasesFailed()
                return
            }
            self.availableParcels = parcels

            for (index, parcel) in parcels.enumerated() {
                let button = UIButton()
                button.translatesAutoresizingMaskIntoConstraints = false
                button.heightAnchor.constraint(equalTo: button.widthAnchor, multiplier: 4.0/20.0).isActive = true
                button.layer.cornerRadius = 7.5
                button.layer.borderColor = UIColor.white.cgColor
                if #available(iOS 13.0, *) {
                    button.backgroundColor = .systemIndigo
                } else {
                    button.backgroundColor = .systemPurple
                }
                button.setTitleColor(.white, for: .normal)

                let title = "\(String(describing: parcel.storageTier)) \(parcel.price) / \(parcel.subscriptionPeriod)"
                let attributedTitle = NSMutableAttributedString(string: title, attributes: [
                    NSAttributedString.Key.font: UIFont.systemFont(ofSize: 19.0),
                    NSAttributedString.Key.foregroundColor: UIColor.white   // needed in iOS 12 for text to appear as white despite setting title color
                ])
                let boldFontAttribute: [NSAttributedString.Key: Any] = [
                    NSAttributedString.Key.font: UIFont.boldSystemFont(ofSize: 19.0),
                    NSAttributedString.Key.foregroundColor: UIColor.white   // needed in iOS 12 for text to appear as white despite setting title color
                ]
                let range = (title as NSString).range(of: parcel.price)
                attributedTitle.addAttributes(boldFontAttribute, range: range)
                button.setAttributedTitle(attributedTitle, for: .normal)

                button.tag = index
                button.addTarget(self, action: #selector(self.purchase(_:)), for: .touchUpInside)
                self.stackView.addArrangedSubview(button)
            }

            purchasesController.entitled { [weak self] storageTier in
                guard let self = self else {
                    return
                }
                self.headerLabel.isHidden = false
                self.stackView.isHidden = false

                // select current storage tier
                if let index = self.availableParcels?.firstIndex(where: { $0.storageTier == storageTier }) {
                    if let button = self.stackView.arrangedSubviews[index] as? UIButton {
                        assert(button.tag == index)
                        self.selectedButton = button
                    }
                }
                if storageTier == .free {
                    self.freeButton.isHidden = !self.showFreeButton
                } else {
                    self.entitlementInfo.text = "Thanks for supporting TripUp! You're awesome! 🥳\nYou're currently subscribed to \(String(describing: storageTier))"
                    self.entitlementInfo.isHidden = false
                    if let endClosure = self.endClosure {
                        self.stackView.arrangedSubviews.forEach{ ($0 as? UIButton)?.drawEnabled(false) }
                        endClosure()
                    }
                }
                self.activityIndicator.stopAnimating()
            }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        animatedGradient?.startAnimating()
    }

    deinit {
        removeAnimatedGradientObservers()
    }

    @IBAction func purchase(_ sender: UIButton) {
        guard sender != freeButton else {
            endClosure?()
            return
        }
        guard let parcel = availableParcels?[sender.tag] else { assertionFailure("parcels: \(String(describing: availableParcels)); tag: \(sender.tag)"); return }
        navigationController?.navigationBar.backItem?.setHidesBackButton(true, animated: true)
        stackView.arrangedSubviews.forEach{ ($0 as? UIButton)?.drawEnabled(false) }
        freeButton.drawEnabled(false)

        activityIndicator.startAnimating()
        purchasesController?.purhase(parcel) { [weak self] success in
            self?.navigationController?.navigationBar.backItem?.setHidesBackButton(false, animated: true)
            self?.stackView.arrangedSubviews.forEach{ ($0 as? UIButton)?.drawEnabled(true) }
            self?.freeButton.drawEnabled(true)
            self?.activityIndicator.stopAnimating()

            if success {
                self?.entitlementInfo.text = "Thanks for supporting TripUp! You're awesome! 🥳\nYou're currently subscribed to \(String(describing: parcel.storageTier))"
                self?.entitlementInfo.isHidden = false
                self?.selectedButton?.drawBorder(false)
                self?.selectedButton = sender
                self?.endClosure?()
            } else {
                self?.selectedButton?.isEnabled = false
                self?.view.makeToastie("There was an error completing this purchase. Please try again", position: .top)
            }
        }
    }

    private func loadPurchasesFailed() {
        activityIndicator.stopAnimating()
        view.makeToastie("There was a problem retrieving storage purchase options", duration: 10.0, position: .center)
        if showFreeButton {
            freeButton.isHidden = false
        }
    }
}

fileprivate extension UIButton {
    func drawBorder(_ value: Bool) {
        if value {
            layer.borderWidth = 4.0
            isEnabled = false
        } else {
            layer.borderWidth = 0.0
        }
    }

    func drawEnabled(_ value: Bool) {
        isEnabled = value
        alpha = value ? 1 : 0.5
    }
}
