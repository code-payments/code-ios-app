import Foundation

/// Validates a free-form phone number string and returns the parsed `Phone`.
///
/// Parsing is delegated to `Phone` (PhoneNumberKit); the resulting E.164 form
/// is then checked against the server's PGV rule. Callers submit the output's
/// `e164`, never the raw input.
public struct PhoneValidator: Validator {

    public init() {}

    public func validate(_ input: String) -> Phone? {
        guard let phone = Phone(input) else {
            return nil
        }

        guard phone.e164.wholeMatch(of: Self.pattern) != nil else {
            return nil
        }

        return phone
    }

    /// PGV regex from `FlipcashAPI/Core/proto/phone/v1/model.proto`.
    private nonisolated(unsafe) static let pattern = /^\+[1-9]\d{1,14}$/
}
