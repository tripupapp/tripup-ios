//
//  NewGroup.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 17/07/2018.
//  Copyright © 2018 Vinoth Ramiah. All rights reserved.
//

import Foundation
import UIKit

enum UserSelectionDelegateResult {
    case success
    case failure(String)
}

protocol UserSelectionDelegate: AnyObject {
    func selected<T>(users: T?, callback: @escaping (UserSelectionDelegateResult) -> Void) where T: Collection, T.Element == User    // users is nil if no users (other than primary user) are selected
}

protocol UserSelectionViewDelegate: AnyObject {
    var contactAccess: Bool { get }
    func presentContactPicker()
    func presentShareSheet(items: [Any])
    func present(message: String)
    func activity(_ show: Bool)
}

class UserSelectionView: UIViewController {
    @IBOutlet var tableView: UITableView!
    @IBOutlet var permissionsView: UIView!

    var loadModally: Bool!
    var preselectedIDs = [UUID]()
    weak var delegate: UserSelectionDelegate?

    private var primaryUser: User!
    private var userManager: UserManager!
    private let contactsProvider = ContactsManager()
    private var tableViewDelegate: UserSelectionViewModel!

    func initialise(primaryUser: User, userManager: UserManager) {
        self.primaryUser = primaryUser
        self.userManager = userManager

        contactsProvider.pickerDelegate = self
    }

    func assertDependencies() {
        assert(loadModally != nil)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        assertDependencies()

        if loadModally {
            self.navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(UserSelectionView.CreateTrip(_:)))
            self.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(UserSelectionView.Dismiss(_:)))
        }

        var users = Set(userManager.allUsers.values)
        users.remove(primaryUser)
        tableViewDelegate = UserSelectionViewModel(primaryUser: primaryUser, users: users, preselectedIDs: Set(preselectedIDs))
        tableViewDelegate.userSelectionViewDelegate = self
        tableView.delegate = tableViewDelegate
        tableView.dataSource = tableViewDelegate

        userManager.addObserver(self)
        permissionsView.isHidden = contactsProvider.authorized
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        let contactsAuthStatusBeforeRequest = contactsProvider.authorized
        contactsProvider.requestAccess { [weak self] authorized in
            if contactsAuthStatusBeforeRequest != authorized {
                DispatchQueue.main.sync {
                    UIView.animate(withDuration: 0.3) {
                        self?.permissionsView.isHidden = authorized
                        self?.tableView.reloadData()    // remove row 0 (manual selection) by reloading table view
                    }
                }
            }
            self?.userManager?.refreshUsers(preselectedContacts: nil, callback: nil)
        }
    }

    @objc func Dismiss(_ sender: UIBarButtonItem!) {
        userManager.removeObserver(self)
        self.dismiss(animated: true, completion: nil)
    }

    private func delegateResult(_ result: UserSelectionDelegateResult) {
        switch result {
        case .success:
            self.dismiss(animated: true, completion: nil)
        case .failure(let message):
            view.makeToastie(message)
            self.navigationController?.navigationBar.isUserInteractionEnabled = true
            self.navigationController?.navigationBar.alpha = 1.0
            tableView.allowsMultipleSelection = true
        }
    }

    @IBAction func CreateTrip(_ sender: UIBarButtonItem) {
        self.navigationController?.navigationBar.isUserInteractionEnabled = false
        self.navigationController?.navigationBar.alpha = 0.5

        tableView.allowsSelection = false
        delegate?.selected(users: tableViewDelegate.selectedUsers(for: tableView.indexPathsForSelectedRows), callback: delegateResult(_:))
    }
}

extension UserSelectionView: UserObserver {
    func new(_ users: Set<User>) {
        tableViewDelegate.add(users, to: tableView)
    }

    func removed(_ users: Set<User>) {
        tableViewDelegate.remove(users, from: tableView)
    }

    func updated(_ user: User) {
        tableViewDelegate.update(user, in: tableView)
    }
}

extension UserSelectionView: UserSelectionViewDelegate {
    var contactAccess: Bool {
        return contactsProvider.authorized
    }

    func presentContactPicker() {
        present(contactsProvider.contactPicker, animated: true, completion: nil)
    }

    func presentShareSheet(items: [Any]) {
        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
        present(activityVC, animated: true)
    }

    func present(message: String) {
        view.makeToastie(message, duration: 5.0, position: .center)
    }

    func activity(_ show: Bool) {
        view.makeToastieActivity(show)
    }
}

extension UserSelectionView: ContactsPickerDelegate {
    func selected(contacts: [Contact]) {
        view.makeToastie("Selected contacts will appear here shortly if they are registered with TripUp", duration: 10.0, position: .center)
        userManager.refreshUsers(preselectedContacts: contacts, callback: nil)
    }
}

fileprivate class UserSelectionViewModel: NSObject {
    private let contactSelectionCellID = "userSelectionManual"
    private let userCellID = "userCell"

    weak var userSelectionViewDelegate: UserSelectionViewDelegate?
    private var primaryUser: User
    private var users = [User]() {
        didSet {
            self.users.sort()
        }
    }
    private let preselectedIDs: Set<UUID>

    init<T>(primaryUser: User, users: T, preselectedIDs: Set<UUID>) where T: Collection, T.Element == User {
        self.primaryUser = primaryUser
        self.preselectedIDs = preselectedIDs
        self.users = users.sorted()
    }

    func selectedUsers(for indexPaths: [IndexPath]?) -> [User]? {
        guard let indexPaths = indexPaths, indexPaths.isNotEmpty, users.isNotEmpty else { return nil }
        precondition(indexPaths.allSatisfy{ $0.section == 2 })
        return indexPaths.map{ users[$0.row] }
    }

    private func ids(at indexPaths: [IndexPath]?) -> [UUID]? {
        guard let indexPaths = indexPaths else { return nil }
        precondition(indexPaths.allSatisfy{ $0.section == 2 })
        return indexPaths.map{ users[$0.row].uuid }
    }

    private func selectIDs(_ selectedIDs: [UUID]?, in tableView: UITableView) {
        guard let selectedIDs = selectedIDs else { return }
        for id in selectedIDs {
            guard let index = users.firstIndex(where: { $0.uuid == id }) else { assertionFailure(); continue }
            tableView.selectRow(at: IndexPath(row: index, section: 2), animated: false, scrollPosition: .none)
        }
    }

    func add(_ users: Set<User>, to tableView: UITableView) {
        let selectedIDs = ids(at: tableView.indexPathsForSelectedRows)
        self.users = Array(users.union(self.users))
        tableView.reloadData()
        selectIDs(selectedIDs, in: tableView)
    }

    func remove(_ users: Set<User>, from tableView: UITableView) {
        let selectedIDs = ids(at: tableView.indexPathsForSelectedRows)
        self.users = Array(Set(self.users).subtracting(users))
        tableView.reloadData()
        selectIDs(selectedIDs, in: tableView)
    }

    func update(_ updatedUser: User, in tableView: UITableView) {
        if updatedUser.uuid == primaryUser.uuid {
            primaryUser = updatedUser
            tableView.reloadRows(at: [IndexPath(row: 0, section: 1)], with: .automatic)
        } else {
            let selectedIDs = ids(at: tableView.indexPathsForSelectedRows)
            var users = self.users
            if let index = users.firstIndex(where: { $0.uuid == updatedUser.uuid }) {
                users.remove(at: index)
            }
            users.append(updatedUser)
            self.users = users
            tableView.reloadData()
            selectIDs(selectedIDs, in: tableView)
        }
    }

    @objc private func loadPrimaryUserlink() {
        userSelectionViewDelegate?.activity(true)
        UniversalLinksService.shared.generate(forUser: primaryUser) { url in
            if let url = url {
                self.userSelectionViewDelegate?.presentShareSheet(items: [url])
            } else {
                self.userSelectionViewDelegate?.present(message: "Unable to generate your personal link. Please try again.")
            }
            self.userSelectionViewDelegate?.activity(false)
        }
    }
}

extension UserSelectionViewModel: UITableViewDataSource {
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cellIdentifier = indexPath.section == 0 ? contactSelectionCellID : userCellID
        let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifier, for: indexPath)
        cell.accessoryView = nil
        switch indexPath.section {
        case 0:
            break
        case 1:
            cell.textLabel?.text = primaryUser.localContact?.name ?? "You"
            cell.textLabel?.isEnabled = false
            cell.detailTextLabel?.text = primaryUser.localContact?.addressable ?? primaryUser.uuid.string
            let shareButton = UIButton(type: .custom)
            shareButton.setTitle(nil, for: .normal)
            shareButton.setImage(UIImage(systemName: "square.and.arrow.up"), for: .normal)
            shareButton.addTarget(self, action: #selector(loadPrimaryUserlink), for: .touchUpInside)
            shareButton.sizeToFit()
            cell.accessoryView = shareButton
        case 2:
            let user = users[indexPath.row]
            cell.textLabel?.text = user.localContact?.name ?? "Tripper"
            cell.textLabel?.isEnabled = !preselectedIDs.contains(user.uuid)    // can't remove users from group once added, for now...
            cell.detailTextLabel?.text = user.localContact?.addressable ?? user.uuid.string
            cell.accessoryType = (tableView.indexPathsForSelectedRows?.contains(indexPath) ?? preselectedIDs.contains(user.uuid)) ? .checkmark : .none
        default:
            fatalError("unexpected section in table")
        }
        return cell
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0, 1:
            return 1
        case 2:
            return users.count
        default:
            return 0
        }
    }

    func numberOfSections(in tableView: UITableView) -> Int {
        return users.isEmpty ? 2 : 3
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 1:
            return " "
        case 2:
            return " "
        default:
            return nil
        }
    }
}

extension UserSelectionViewModel: UITableViewDelegate {
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 0
//        return section == 0 ? 0 : tableView.sectionHeaderHeight
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return 0
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if indexPath.section == 0, let userSelectionViewDelegate = userSelectionViewDelegate, userSelectionViewDelegate.contactAccess {
            return 0
        }
        return 56
    }

    func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        if indexPath.section == 1 {
            return nil
        }
        if indexPath.section == 2, preselectedIDs.contains(users[indexPath.row].uuid) {
            return nil
        }
        return indexPath
    }

    func tableView(_ tableView: UITableView, willDeselectRowAt indexPath: IndexPath) -> IndexPath? {
        if indexPath.section == 1 {
            return nil
        }
        // can't remove users from group once added, for now...
        if indexPath.section == 2, preselectedIDs.contains(users[indexPath.row].uuid) {
            return nil
        }
        return indexPath
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if indexPath.section == 0 {
            userSelectionViewDelegate?.presentContactPicker()
            tableView.deselectRow(at: indexPath, animated: true)
        } else if indexPath.section == 2 {
            guard let cell = tableView.cellForRow(at: indexPath) else { return }
            precondition(cell.reuseIdentifier == userCellID)
            cell.accessoryType = .checkmark
        }
    }

    func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        guard let cell = tableView.cellForRow(at: indexPath) else { return }
        cell.accessoryType = .none
    }
}
