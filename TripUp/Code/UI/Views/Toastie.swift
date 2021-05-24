//
//  Toastie.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 25/04/2020.
//  Copyright © 2020 Vinoth Ramiah. All rights reserved.
//

import Foundation
import Toast_Swift

/*
 NOTE: For Toast_Swift library, use view.superview?.makeToastie if making a toast with bottom position inside a tableView or indeed any view that scrolls – otherwise the toast will not be offset correctly
  More info: https://github.com/scalessec/Toast-Swift/issues/20#issuecomment-214555818
 */

extension UIView {
    func makeToastie(_ message: String?, duration: TimeInterval = ToastManager.shared.duration, position: ToastPosition = ToastManager.shared.position, title: String? = nil, image: UIImage? = nil, style: ToastStyle = ToastManager.shared.style, completion: ((_ didTap: Bool) -> Void)? = nil) {
        self.makeToast(message, duration: duration, position: position, title: title, image: image, style: style, completion: completion)
    }

    func makeToastieActivity(_ show: Bool) {
        if show {
            self.makeToastActivity(.center)
        } else {
            self.hideToastActivity()
        }
    }
}
