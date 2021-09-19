//
//  InAppPurchaseView.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 27/03/2020.
//  Copyright © 2020 Vinoth Ramiah. All rights reserved.
//

import Foundation
import UIKit

class InAppPurchaseView: UIViewController {
    @IBOutlet var product1: UIButton!
    @IBOutlet var product2: UIButton!
    @IBOutlet var product3: UIButton!
    @IBOutlet var popupView: UIView!
    @IBOutlet var textView: UITextView!
    @IBOutlet var parcelPanel: UIStackView!
    @IBOutlet var activityIndicator: UIActivityIndicatorView!

    private let log = Logger.self
    private var purchasesController: PurchasesController!
    private var parcels = [PurchasesController.Parcel]()
    private var productButtons = [UIButton]()

    func initialise(purchasesController: PurchasesController) {
        self.purchasesController = purchasesController
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        product1.isHidden = true
        product2.isHidden = true
        product3.isHidden = true

        productButtons.append(product1)
        productButtons.append(product2)
        productButtons.append(product3)

        purchasesController.offers { [weak self] parcels in
            guard let self = self, let parcels = parcels else { return }

            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            switch parcels.count {
            case 3:
                let parcel3 = parcels[2]
                self.product3.setAttributedTitle(NSAttributedString(string: "\(parcel3.price)\n\(parcel3.subscriptionPeriod)", attributes: [.paragraphStyle: paragraph]), for: .normal)
                self.product3.isHidden = false
                fallthrough
            case 2:
                let parcel2 = parcels[1]
                self.product2.setAttributedTitle(NSAttributedString(string: "\(parcel2.price)\n\(parcel2.subscriptionPeriod)", attributes: [.paragraphStyle: paragraph]), for: .normal)
                self.product2.isHidden = false
                fallthrough
            case 1:
                let parcel1 = parcels[0]
                self.product1.setAttributedTitle(NSAttributedString(string: "\(parcel1.price)\n\(parcel1.subscriptionPeriod)", attributes: [.paragraphStyle: paragraph]), for: .normal)
                self.product1.isHidden = false
            default:
                preconditionFailure("packages count: \(parcels.count)")
            }
            self.parcels = parcels

            self.purchasesController.entitled { [weak self] currentStorageTier in
                if let index = self?.parcels.firstIndex(where: { $0.storageTier == currentStorageTier }) {
                    let productButton = self?.productButtons[index]
                    productButton?.isEnabled = false
                    productButton?.alpha = 0.5
                }
            }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        textView.setContentOffset(.zero, animated: true)    // needed otherwise textview starts scrolled at bottom on at least iPhone 5S, iOS 12.4
        textView.flashScrollIndicators()
    }

    @IBAction func dismiss(_ sender: UIBarButtonItem) {
        self.dismiss(animated: true, completion: nil)
    }

    @IBAction func purchase(_ sender: UIButton) {
        parcelPanel.isHidden = true
        activityIndicator.startAnimating()
        let parcel = parcels[sender.tag]
        purchasesController.purhase(parcel) { [weak self] success in
            guard let self = self else { return }
            if success {
                self.dismiss(animated: true, completion: nil)
            } else {
                self.parcelPanel.isHidden = false
                self.activityIndicator.stopAnimating()
                self.popupView.makeToast("Failed to purchase TripUp Pro. Please try again", position: .top)
            }
        }
    }
}
