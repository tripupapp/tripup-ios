//
//  WarningHeaderView.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 14/09/2020.
//  Copyright © 2020 Vinoth Ramiah. All rights reserved.
//

import UIKit

@IBDesignable public class WarningHeaderView: UIView {

    /*
    // Only override draw() if you perform custom drawing.
    // An empty implementation adversely affects performance during animation.
    override func draw(_ rect: CGRect) {
        // Drawing code
    }
    */

    var contentView : UIView?
    @IBOutlet public var alertIcon: UIImageView!
    @IBOutlet public var label: UILabel!

    override init(frame: CGRect) {
        super.init(frame: frame)
        xibSetup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        xibSetup()
    }

    // https://stackoverflow.com/a/37668821/2728986
    private func xibSetup() {
        contentView = loadViewFromNib()

        // use bounds not frame or it'll be offset
        contentView!.frame = bounds

        // Make the view stretch with containing view
        contentView!.autoresizingMask = [.flexibleHeight, .flexibleWidth]

        // Adding custom subview on top of our view (over any custom drawing > see note below)
        addSubview(contentView!)

        if #available(iOS 13.0, *) {
            alertIcon.image = UIImage(systemName: "exclamationmark.circle.fill")
        }
    }

    private func loadViewFromNib() -> UIView! {
        // https://stackoverflow.com/a/35700192/2728986
        let bundle = Bundle(for: WarningHeaderView.self)
        let view = bundle.loadNibNamed(String(describing: WarningHeaderView.self), owner: self, options: nil)![0] as! UIView
        return view
    }
}
