import Foundation
import FlipcashAPI

extension Ocp_Transaction_V1_ErrorDetails {
    static func reasonString(_ reason: String) -> Self {
        var reasonString = Ocp_Transaction_V1_ReasonStringErrorDetails()
        reasonString.reason = reason

        var details = Ocp_Transaction_V1_ErrorDetails()
        details.reasonString = reasonString
        return details
    }

    static func denied(
        code: Ocp_Transaction_V1_DeniedErrorDetails.Code,
        reason: String
    ) -> Self {
        var deniedDetails = Ocp_Transaction_V1_DeniedErrorDetails()
        deniedDetails.code = code
        deniedDetails.reason = reason

        var details = Ocp_Transaction_V1_ErrorDetails()
        details.denied = deniedDetails
        return details
    }
}
