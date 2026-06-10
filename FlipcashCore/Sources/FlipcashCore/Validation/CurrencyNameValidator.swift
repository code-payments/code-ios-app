import Foundation

/// Validates a launchpad currency name: printable ASCII, no leading or
/// trailing space, 1–32 characters.
///
/// Returns the name unchanged — rejecting rather than trimming, because the
/// moderation attestation is bound to the exact string that is later
/// submitted to the Launch RPC.
public struct CurrencyNameValidator: Validator {

    public static let maxLength = 32

    public init() {}

    public func validate(_ input: String) -> String? {
        guard !input.isEmpty, input.count <= Self.maxLength else {
            return nil
        }

        guard input.wholeMatch(of: Self.pattern) != nil else {
            return nil
        }

        return input
    }

    /// PGV regex from `FlipcashAPI/Payments/proto/currency/v1/currency_service.proto`.
    private nonisolated(unsafe) static let pattern = #/^[!-~]([ -~]*[!-~])?$/#
}
