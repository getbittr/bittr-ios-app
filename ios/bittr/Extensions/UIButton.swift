//
//  UIButton.swift
//  bittr
//
//  Despite the filename, this defines boundString on UIView so it's
//  available on any view (alert overlays, graph cards, etc.) — not just
//  buttons. UIButton inherits from UIView, so button call sites are
//  unchanged.
//

import UIKit

private var boundStringKey: UInt8 = 0

extension UIView {
    // Associated-object storage so accessibilityIdentifier stays free for Maestro test IDs.
    // Use this to carry the value a view represents (text to copy, ID to open,
    // a tag for finding the view among siblings, etc.) between the configuration
    // site and the code that reads it back.
    var boundString: String? {
        get { objc_getAssociatedObject(self, &boundStringKey) as? String }
        set { objc_setAssociatedObject(self, &boundStringKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
}
