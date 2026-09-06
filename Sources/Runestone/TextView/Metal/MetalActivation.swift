import Foundation

enum MetalActivation {
    static let defaultsKey = "RunestoneMetalRendering"

    /// Single resolution function. Call from `TextView` init and on flag/defaults change.
    static func resolved(
        property: Bool,
        deviceAvailable: Bool,
        defaults: Bool?
    ) -> Bool {
        guard deviceAvailable else {
            return false
        }
        if defaults == false {
            return false
        }
        if property == false {
            return false
        }
        if defaults == true {
            return true
        }
        return property
    }
}
