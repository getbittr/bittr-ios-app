//
//  UIButton.swift
//  bittr
//

import UIKit

private var boundStringKey: UInt8 = 0

extension UIButton {
    // Associated-object storage so accessibilityIdentifier stays free for Maestro test IDs.
    // Use this to carry the value a button represents (text to copy, ID to open, etc.)
    // between the configuration site and its @IBAction handler.
    var boundString: String? {
        get { objc_getAssociatedObject(self, &boundStringKey) as? String }
        set { objc_setAssociatedObject(self, &boundStringKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
}
