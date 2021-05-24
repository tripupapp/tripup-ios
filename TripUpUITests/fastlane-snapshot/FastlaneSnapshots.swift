//
//  FastlaneSnapshots.swift
//  FastlaneSnapshots
//
//  Created by Vinoth Ramiah on 12/03/2020.
//  Copyright © 2020 Vinoth Ramiah. All rights reserved.
//

import XCTest

class FastlaneSnapshots: XCTestCase {

    /**
     Notes:
     - Dark mode setting appears to reset simulator state for some reason. Best to set dark mode manually on simulator before running snapshot
     - App Store Compatible Screenshots: use `--devices "iPhone 11 Pro Max,iPhone 8 Plus"`
     Commands:
     - fastlane snapshot run -X -only-testing:TripUpUITests/FastlaneSnapshots/testSnapshotLibraryView --devices "iPhone X,iPhone X Secondary"

     App Store Step by Step:
     1. fastlane snapshot run -X -only-testing:TripUpUITests/FastlaneSnapshots/testSnapshotLibraryView --devices "iPhone 11 Pro Max,iPhone 8 Plus"
     2. fastlane snapshot run -X -only-testing:TripUpUITests/FastlaneSnapshots/testSnapshotPhotoView --devices "iPhone 11 Pro Max,iPhone 8 Plus"
     3. fastlane snapshot run -X -only-testing:TripUpUITests/FastlaneSnapshots/testSnapshotLoginsView --devices "iPhone 11 Pro Max,iPhone 8 Plus"
     4. Enable Dark Mode manually for Simulators
     5. fastlane snapshot run -X -only-testing:TripUpUITests/FastlaneSnapshots/testSnapshotAlbumsView --devices "iPhone 11 Pro Max,iPhone 8 Plus"
     6. fastlane snapshot run -X -only-testing:TripUpUITests/FastlaneSnapshots/testSnapshotPreferencesView --devices "iPhone 11 Pro Max,iPhone 8 Plus"
     7. fastlane snapshot run -X -only-testing:TripUpUITests/FastlaneSnapshots/testSnapshotPasswordView --devices "iPhone 11 Pro Max,iPhone 8 Plus"
     */

    private var app: XCUIApplication!

    override func setUp() {
        // Put setup code here. This method is called before the invocation of each test method in the class.
        app = XCUIApplication()
        app.launchEnvironment = ["UITest-Screenshots": "True"]
        setupSnapshot(app)

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        app.terminate()
        app = nil
    }

    func testSnapshotLibraryView() {
        app.launch()
        sleep(10)
        snapshot("LibraryView")
    }

    func testSnapshotAlbumsView() {
        app.launch()
        sleep(10)
        app.tabBars["Tab Bar"].buttons["Albums"].tap()
        sleep(5)
        snapshot("AlbumsView")
    }

    func testSnapshotPhotoView() {
        app.launch()
        sleep(10)
        app.tabBars["Tab Bar"].buttons["Albums"].tap()
        sleep(5)
        let element = app.collectionViews.children(matching: .cell).element(boundBy: 0).children(matching: .other).element.children(matching: .other).element
        element.tap()
        sleep(5)
        snapshot("PhotoView")
    }

    func testSnapshotPreferencesView() {
        app.launch()
        sleep(10)
        app.tabBars["Tab Bar"].buttons["Settings"].tap()
        sleep(5)
        snapshot("PreferencesView")
    }

    func testSnapshotLoginsView() {
        app.launch()
        sleep(10)
        app.tabBars["Tab Bar"].buttons["Settings"].tap()
        app.tables/*@START_MENU_TOKEN@*/.staticTexts["Logins"]/*[[".cells.staticTexts[\"Logins\"]",".staticTexts[\"Logins\"]"],[[[-1,1],[-1,0]]],[0]]@END_MENU_TOKEN@*/.tap()
        sleep(5)
        snapshot("LoginsView")
    }

    func testSnapshotPasswordView() {
        app.launch()
        sleep(10)
        app.tabBars["Tab Bar"].buttons["Settings"].tap()
        app.tables.staticTexts["Password"].tap()
        sleep(5)
        snapshot("PasswordView")
    }
}
