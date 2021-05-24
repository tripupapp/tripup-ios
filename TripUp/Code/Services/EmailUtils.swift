//
//  EmailUtils.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 14/05/2020.
//  Copyright © 2020 Vinoth Ramiah. All rights reserved.
//

import Foundation

protocol EmailUtils {
    func isEmail(_ string: String) -> Bool
}

class EmailService {}

extension EmailService: EmailUtils {
    /** https://emailregex.com **/
    func isEmail(_ string: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        return NSPredicate(format: "SELF MATCHES %@", emailRegex).evaluate(with: string)
    }
}
