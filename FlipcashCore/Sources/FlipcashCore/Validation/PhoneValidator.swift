import Foundation

/// The outcome of validating a phone number that has some input: why it isn't
/// yet valid, or the parsed number. Nothing-entered is the validator's `nil`.
public enum PhoneValidation: Equatable, Sendable {
    /// Too few digits to be judged — the user may still be typing.
    case incomplete
    /// Cannot become valid as typed.
    case invalid
    /// A complete, valid number.
    case valid(Phone)
}

/// Validates a free-form phone number string against the country the user
/// selected.
///
/// Parsing is delegated to `Phone` (PhoneNumberKit) using `region` so the flag
/// is honoured; a valid number's E.164 form is checked against the server's PGV
/// rule. Callers submit `valid`'s `e164`, never the raw input.
public struct PhoneValidator: Validator {

    private let region: Region

    public init(region: Region) {
        self.region = region
    }

    /// Classifies `input`: `nil` when nothing has been entered, otherwise the
    /// `PhoneValidation` describing why it isn't yet valid or the parsed number.
    public func validate(_ input: String) -> PhoneValidation? {
        guard input.contains(where: \.isNumber) else {
            return nil
        }

        if let phone = Phone(input, defaultRegion: region), phone.e164.wholeMatch(of: Self.pattern) != nil {
            return .valid(phone)
        }

        // Without a known length we can't tell "still typing" from "wrong", so
        // stay quiet rather than flash an error on the first digit.
        guard let expectedLength = Phone.expectedNationalLength(for: region) else {
            return .incomplete
        }

        return input.filter(\.isNumber).count >= expectedLength ? .invalid : .incomplete
    }

    /// PGV regex from `FlipcashAPI/Core/proto/phone/v1/model.proto`.
    private nonisolated(unsafe) static let pattern = /^\+[1-9]\d{1,14}$/
}
