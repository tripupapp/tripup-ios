//
//  NewStreamView.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 21/06/2017.
//  Copyright © 2017 Vinoth Ramiah. All rights reserved.
//

import Foundation
import UIKit

class NewStreamView: UIViewController {
    @IBOutlet var streamNameField: UITextField!
    @IBOutlet var nextButton: UIBarButtonItem!
    @IBOutlet var quoteLabel: UILabel!

    private var groupManager: GroupManager?
    private var dependencyInjector: DependencyInjector?

    private var quotes: [String]? = {
        if let plistURL = Bundle.main.url(forResource: "quotes", withExtension: "plist") {
            if let plistArray = NSArray(contentsOf: plistURL) as? [String] {
                return plistArray
            }
        }
        return nil
    }()

    private var newGroup: Group?

    func initialise(groupManager: GroupManager?, dependencyInjector: DependencyInjector?) {
        self.groupManager = groupManager
        self.dependencyInjector = dependencyInjector
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        if let quote = quotes?.randomElement() {
            quoteLabel.text = quote
        }

        streamNameField.keyboardToolbar.doneBarButton.setTarget(self, action: #selector(segueToNextView))
    }

    @IBAction func textFieldChanged(_ sender: UITextField) {
        guard let streamName = streamNameField.text else { return }
        nextButton.isEnabled = !streamName.isEmpty
    }

    @IBAction func segueToNextView() {
        if let text = streamNameField.text, text.isNotEmpty {
            performSegue(withIdentifier: "addTrippers", sender: streamNameField)
        }
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        guard let userSelectionView = segue.destination as? UserSelectionView else { return }
        dependencyInjector?.initialise(userSelectionView)
        userSelectionView.loadModally = false
        userSelectionView.delegate = self
        streamNameField.resignFirstResponder()
    }

    @IBAction func dismiss() {
        streamNameField.resignFirstResponder()
        self.dismiss(animated: true, completion: nil)
    }
}

extension NewStreamView: UserSelectionDelegate {
    func selected<T>(users: T?, callback: @escaping (UserSelectionDelegateResult) -> Void) where T: Collection, T.Element == User {
        guard let groupName = streamNameField.text, groupName.isNotEmpty else { assertionFailure(); return }

        let returnNewGroup = { (name: String, callback: @escaping (_ success: Bool, _ group: Group?) -> Void) in
            if let newGroup = self.newGroup {
                callback(true, newGroup)
            } else {
                self.groupManager?.createGroup(name: name, callback: callback)
            }
        }

        returnNewGroup(groupName) { (success, group) in
            guard success, let group = group else { callback(.failure("Failed to create album. Try again in a moment.")); return }
            self.newGroup = group
            if let users = users {
                self.groupManager?.addUsers(users, to: group) { success in
                    if success {
                        callback(.success)
                    } else {
                        callback(.failure("Created album but failed to add the selected trippers. Try adding them again in a moment."))
                    }
                }
            } else {
                callback(.success)
            }
        }
    }
}
