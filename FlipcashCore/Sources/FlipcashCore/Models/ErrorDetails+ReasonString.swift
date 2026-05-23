import Foundation
import FlipcashAPI

extension Sequence where Element == Ocp_Transaction_V1_ErrorDetails {
    /// Non-empty `ReasonStringErrorDetails.reason` values, in order.
    public var reasonStrings: [String] {
        compactMap { detail in
            guard case .reasonString(let reasonString) = detail.type,
                  !reasonString.reason.isEmpty else { return nil }
            return reasonString.reason
        }
    }

    /// First non-empty reason string, or `nil` when none is present.
    public var firstReasonString: String? {
        reasonStrings.first
    }
}
