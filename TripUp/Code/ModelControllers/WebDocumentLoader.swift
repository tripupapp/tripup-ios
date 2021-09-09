//
//  WebDocumentLoader.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 04/04/2020.
//  Copyright © 2020 Vinoth Ramiah. All rights reserved.
//

import Foundation
import WebKit

struct WebDocument {
    let bundleResource: (resource: String, extension: String)
    let verificationString: String
    let renderedFilename: String
}

class WebDocumentLoader: NSObject {
    static let shared = WebDocumentLoader()

    private var document: WebDocument?
    private let webView = WKWebView()

    private override init() {
        super.init()
        webView.navigationDelegate = self
    }

    func load(document: WebDocument) throws {
        guard let filepath = Bundle.main.path(forResource: document.bundleResource.resource, ofType: document.bundleResource.extension) else {
            throw "unable to obtain file path for bundle resource: \(document.bundleResource.resource).\(document.bundleResource.extension)"
        }
        let html = try String(contentsOfFile: filepath)
        self.document = document
        let header = "<header><meta name='viewport' content='width=device-width, initial-scale=1.0, maximum-scale=1.0, minimum-scale=1.0, user-scalable=no'></header>"
        webView.loadHTMLString(header + html, baseURL: nil)
    }
}

extension WebDocumentLoader: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript("document.documentElement.outerHTML.toString()") { [unowned self] (html: Any?, error: Error?) in
            if let document = self.document, let documentString = html as? String, documentString.contains(document.verificationString) {
                try? documentString.write(to: Globals.Directories.legal.appendingPathComponent(document.renderedFilename, isDirectory: false), atomically: true, encoding: .utf8)
            }
        }
    }
}
