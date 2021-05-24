//
//  CloudProgressSync.swift
//  TripUp
//
//  Created by Vinoth Ramiah on 25/02/2020.
//  Copyright © 2020 Vinoth Ramiah. All rights reserved.
//

import UIKit

@IBDesignable public class CloudProgressSync: UIView {
    var contentView : UIView?
    @IBOutlet public var progressView: UIProgressView!
    @IBOutlet public var progressLabel: UILabel!

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
    }

    private func loadViewFromNib() -> UIView! {
        // https://stackoverflow.com/a/35700192/2728986
        let bundle = Bundle(for: CloudProgressSync.self)
        let view = bundle.loadNibNamed(String(describing: CloudProgressSync.self), owner: self, options: nil)![0] as! UIView
        return view
    }

    public func update(completed: Int, total: Int) {
        if completed == total {
            if !isHidden {
                progressView.setProgress(1.0, animated: true)
                progressLabel.text = "Cloud sync completed"
                UIView.animate(withDuration: 0.3, delay: 6.0, options: .allowUserInteraction, animations: {
                    self.isHidden = true
                }, completion: nil)
            }
        } else {
            progressView.progress = Float(completed) / Float(total)
            let itemsLeft = total - completed
            progressLabel.text = "\(itemsLeft) item\(itemsLeft > 1 ? "s": "") left"
            if isHidden {
                UIView.animate(withDuration: 0.3) {
                    self.isHidden = false
                }
            }
        }
    }
}
