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

    /// Non-empty `DeniedErrorDetails.reason` values, in order.
    public var deniedReasons: [String] {
        compactMap { detail in
            guard case .denied(let denied) = detail.type,
                  !denied.reason.isEmpty else { return nil }
            return denied.reason
        }
    }
}
