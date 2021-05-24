//
//  PolicyView.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 03/04/2020.
//  Copyright © 2020 Vinoth Ramiah. All rights reserved.
//

import Foundation
import UIKit
import WebKit

class PolicyView: UIViewController {
    @IBOutlet var policyWebView: WKWebView!

    private var url: URL!

    func initialise(title: String, url: URL) {
        self.title = title
        self.url = url
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        self.navigationController?.setNavigationBarHidden(false, animated: true)

        policyWebView.loadFileURL(url, allowingReadAccessTo: url)
    }
}
