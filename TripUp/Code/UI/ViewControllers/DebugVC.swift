//
//  DebugVC.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 10/04/2021.
//  Copyright © 2021 Vinoth Ramiah. All rights reserved.
//

import Foundation
import UIKit

class DebugVC: UITableViewController {
    @IBOutlet var debugLogSwitch: UISwitch!

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        debugLogSwitch.setOn(UserDefaults.standard.bool(forKey: UserDefaultsKey.DebugLogs.rawValue), animated: false)
    }

    override func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        switch (indexPath.section, indexPath.item) {
        case (0, 0):    // debug log switch toggle
            return nil
        default:
            return indexPath
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        switch (indexPath.section, indexPath.item) {
        case (0, 1):    // Export Log File
            exportLogFile()
            tableView.deselectRow(at: indexPath, animated: false)
        default:
            break
        }
    }

    @IBAction func debugLogSwitchToggled(_ sender: UISwitch) {
        Logger.setDebugLevel(on: sender.isOn)
    }

    private func exportLogFile() {
        guard let url = Logger.logFileURL() else {
            view.makeToastie("Could not locate log file")
            return
        }
        let activityViewController = UIActivityViewController(activityItems: [url], applicationActivities: nil)

        view.makeToastieActivity(true)
        present(activityViewController, animated: true) { [unowned self] in
            self.view.makeToastieActivity(false)
        }
    }
}
