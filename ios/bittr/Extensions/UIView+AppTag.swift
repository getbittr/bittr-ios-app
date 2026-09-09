import UIKit
import ObjectiveC.runtime

private struct AssociatedKeys {
    static var appTag: UInt8 = 0
}

extension UIView {

    // String metadata attached to a view — used to ferry data through tap handlers
    // (article slug, settings row id, fee level, etc). Exists so accessibilityIdentifier
    // can stay reserved for Maestro test IDs.
    var appTag: String? {
        get {
            return objc_getAssociatedObject(self, &AssociatedKeys.appTag) as? String
        }
        set {
            objc_setAssociatedObject(self, &AssociatedKeys.appTag, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
}
