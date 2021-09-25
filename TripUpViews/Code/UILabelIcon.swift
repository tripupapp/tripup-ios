//
//  NewStreamInstructionLabel.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 02/12/2019.
//  Copyright © 2019 Vinoth Ramiah. All rights reserved.
//

import Foundation
import UIKit

@IBDesignable public class UILabelIcon: UILabel {
    @IBInspectable public var textToReplace: String? = nil {
        didSet {
            replaceText()
        }
    }

    @IBInspectable public var replacementIcon: UIImage? = nil {
        didSet {
            replaceText()
        }
    }

    @IBInspectable public var verticalOffset: CGFloat = 0.0 {
        didSet {
            replaceText()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        replaceText()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        replaceText()
    }

    public override func prepareForInterfaceBuilder() {
        super.prepareForInterfaceBuilder()
        replaceText()
    }

    private func replaceText() {
        guard let text = text, let textToReplace = textToReplace, let replacementIcon = replacementIcon else { return }
        guard let range = text.range(of: textToReplace) else { return }

        let initialString = NSMutableAttributedString(string: text)

        let imageAttachment = NSTextAttachment()
        imageAttachment.image = replacementIcon

        let replacementString = NSAttributedString(attachment: imageAttachment)
        initialString.replaceCharacters(in: NSRange(range, in: text), with: replacementString)

        self.attributedText = initialString
    }
}
