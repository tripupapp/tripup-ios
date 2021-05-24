//
//  AVFileType.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 28/09/2019.
//  Copyright © 2019 Vinoth Ramiah. All rights reserved.
//

import Foundation
import AVFoundation

extension AVFileType {
    init?(_ uti: String?) {
        guard let uti = uti else { return nil }
        self.init(uti)
    }
}
