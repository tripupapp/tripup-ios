//
//  TimeInterval.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 16/06/2021.
//  Copyright © 2021 Vinoth Ramiah. All rights reserved.
//

import Foundation

extension TimeInterval {
    var formattedString: String? {
        let dateFormatter = DateComponentsFormatter()
        dateFormatter.zeroFormattingBehavior = .pad
        dateFormatter.allowedUnits = [.minute, .second]
        if self >= 3600 {
            dateFormatter.allowedUnits.insert(.hour)
        }
        let formatted = dateFormatter.string(from: self)
        return formatted?.replacingOccurrences(of: "^0", with: "", options: .regularExpression)
    }
}
