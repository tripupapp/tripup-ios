//
//  PhoneNumberUtils.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 09/05/2020.
//  Copyright © 2020 Vinoth Ramiah. All rights reserved.
//

import Foundation
import PhoneNumberKit

protocol PhoneNumberUtils {
    func phoneNumber(from string: String, format: PhoneNumberFormat) -> String?
    func isPhoneNumber(_ string: String) -> Bool
}

extension PhoneNumberUtils {
    func phoneNumber(from string: String, format: PhoneNumberFormat = .e164) -> String? {
        phoneNumber(from: string, format: format)
    }
}

class PhoneNumberService {
    private let phoneNumberKit = PhoneNumberKit()
}

extension PhoneNumberService: PhoneNumberUtils {
    func phoneNumber(from string: String, format: PhoneNumberFormat = .e164) -> String? {
        if let phoneNumber = try? phoneNumberKit.parse(string) {
            return phoneNumberKit.format(phoneNumber, toType: format)
        }
        return nil
    }

    func isPhoneNumber(_ string: String) -> Bool {
        let x = try? phoneNumberKit.parse(string)
        return x != nil
    }
}
