import Foundation
import FlipcashCore

extension Bundle {

    /// FlipcashUI's resource bundle (assets, fonts, emoji catalog).
    static let flipcashUI = packageResources(named: "FlipcashUI_FlipcashUI", fallback: .module)
}
