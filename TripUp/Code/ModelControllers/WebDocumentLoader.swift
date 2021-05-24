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

class WebDocumentLoader {
    class WebDocumentLoaderDelegate: NSObject, WKNavigationDelegate {
        private let document: WebDocument

        init(document: WebDocument) {
            self.document = document
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("document.documentElement.outerHTML.toString()") { (html: Any?, error: Error?) in
                let policyString = html as! String
                if policyString.contains(self.document.verificationString) {
                    try! policyString.write(to: Globals.Directories.legal.appendingPathComponent(self.document.renderedFilename, isDirectory: false), atomically: true, encoding: .utf8)
                }
            }
        }
    }

    private let loader = WKWebView()
    private let loaderDelegate: WebDocumentLoaderDelegate

    init(document: WebDocument) {
        let filepath = Bundle.main.path(forResource: document.bundleResource.resource, ofType: document.bundleResource.extension)!
        let html = try! String(contentsOfFile: filepath)

        loaderDelegate = WebDocumentLoaderDelegate(document: document)
        loader.navigationDelegate = loaderDelegate

        let header = "<header><meta name='viewport' content='width=device-width, initial-scale=1.0, maximum-scale=1.0, minimum-scale=1.0, user-scalable=no'></header>"
        loader.loadHTMLString(header + html, baseURL: nil)
    }
}
