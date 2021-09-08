//
//  ContactsManager.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 05/07/2018.
//  Copyright © 2018 Vinoth Ramiah. All rights reserved.
//

import Foundation
import Contacts
import ContactsUI

struct Contact: Hashable {
    enum ContactType: String, Codable {
        case number
        case email
    }

    let name: String
    let addressable: String
    let localID: String
    let type: ContactType
}

extension Contact: Codable {}

protocol ContactsPickerDelegate: AnyObject {
    func selected(contacts: [Contact])
}

protocol ContactsProvider: AnyObject {
    var authorized: Bool { get }
    var allContacts: [Contact] { get }
    var contactPicker: CNContactPickerViewController { get }
    var pickerDelegate: ContactsPickerDelegate? { get set }
    func requestAccess(completion: @escaping ClosureBool)
}

class ContactsManager: NSObject {
    private let log = Logger.self
    private let store = CNContactStore()
    private let keysToFetch = [
        CNContactPhoneNumbersKey as CNKeyDescriptor,
        CNContactEmailAddressesKey as CNKeyDescriptor,
        CNContactIdentifierKey as CNKeyDescriptor,
        CNContactFormatter.descriptorForRequiredKeys(for: .fullName)
    ]
    private let phoneNumberUtils = PhoneNumberService()
    private let emailUtils = EmailService()
    weak var pickerDelegate: ContactsPickerDelegate?

    private let nameFormatter: CNContactFormatter = {
        let formatter = CNContactFormatter()
        formatter.style = .fullName
        return formatter
    }()
}

extension ContactsManager: ContactsProvider {
    var authorized: Bool {
        return CNContactStore.authorizationStatus(for: .contacts) == .authorized
    }

    var allContacts: [Contact] {
        let fetchRequest = CNContactFetchRequest(keysToFetch: keysToFetch)
        var contacts = [Contact]()
        try? store.enumerateContacts(with: fetchRequest, usingBlock: { [unowned self] contact, _ in
            guard let name = self.nameFormatter.string(from: contact) else { return }

            for phoneNumber in contact.phoneNumbers {
                let number = phoneNumber.value.stringValue
                if let formattedNumber = self.phoneNumberUtils.phoneNumber(from: number, format: .e164) {
                    contacts.append(Contact(name: name, addressable: formattedNumber, localID: contact.identifier, type: .number))
                }
            }

            for emailAddress in contact.emailAddresses {
                let email = emailAddress.value as String
                if self.emailUtils.isEmail(email) {
                    contacts.append(Contact(name: name, addressable: email, localID: contact.identifier, type: .email))
                }
            }
        })
        return contacts
    }

    var contactPicker: CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.predicateForEnablingContact = NSPredicate(format: "phoneNumbers.@count > 0 || emailAddresses.@count > 0", argumentArray: nil)
        picker.delegate = self
        return picker
    }

    func requestAccess(completion: @escaping ClosureBool) {
        store.requestAccess(for: .contacts) { [unowned self] success, error in
            if let error = error {
                self.log.warning(error.localizedDescription)
                completion(false)
            } else {
                completion(success)
            }
        }
    }
}

extension ContactsManager: CNContactPickerDelegate {
    func contactPicker(_ picker: CNContactPickerViewController, didSelect contacts: [CNContact]) {
        guard let pickerDelegate = pickerDelegate else { return }
        var contactsToImport = [Contact]()
        for contact in contacts {
            guard let name = nameFormatter.string(from: contact) else { continue }

            for phoneNumber in contact.phoneNumbers {
                let number = phoneNumber.value.stringValue
                if let formattedNumber = phoneNumberUtils.phoneNumber(from: number, format: .e164) {
                    contactsToImport.append(Contact(name: name, addressable: formattedNumber, localID: contact.identifier, type: .number))
                }
            }

            for emailAddress in contact.emailAddresses {
                let email = emailAddress.value as String
                if emailUtils.isEmail(email) {
                    contactsToImport.append(Contact(name: name, addressable: email, localID: contact.identifier, type: .email))
                }
            }
        }
        if contactsToImport.isNotEmpty {
            pickerDelegate.selected(contacts: contactsToImport)
        }
    }
}
