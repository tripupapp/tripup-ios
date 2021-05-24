//
//  SupportView.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 27/11/2019.
//  Copyright © 2019 Vinoth Ramiah. All rights reserved.
//

import Foundation
import UIKit

class SupportView: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        if let rootVC = self.navigationController as? RootView, rootVC.children.first is LoginView {
            rootVC.setNavigationBarHidden(false, animated: true)
        }
    }

    @IBAction func tappedWhatsApp(_ sender: UITapGestureRecognizer) {
        guard let whatsappURL = URL(string: "https://wa.me/447366120931") else { return }
        UIApplication.shared.open(whatsappURL)
    }

    @IBAction func tappedDiscord(_ sender: UITapGestureRecognizer) {
        guard let discordURL = URL(string: "https://discord.gg/5xCF7Eb") else { return }
        UIApplication.shared.open(discordURL)
    }

    @IBAction func tappedReddit(_ sender: UITapGestureRecognizer) {
        guard let redditURL = URL(string: "https://www.reddit.com/r/tripup") else { return }
        UIApplication.shared.open(redditURL)
    }

    @IBAction func tappedEmail(_ sender: UITapGestureRecognizer) {
        let recipient = "vinoth.ramiah@tripup.app"
        guard let emailURL = URL(string: "mailto:\(recipient)") else { return }
        UIApplication.shared.open(emailURL)
    }
}
