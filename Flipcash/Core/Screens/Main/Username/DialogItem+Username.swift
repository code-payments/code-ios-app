//
//  DialogItem+Username.swift
//  Flipcash
//

import FlipcashCore
import FlipcashUI

extension DialogItem {

    /// The catch-all failure. Named rather than written out twice: the screen
    /// raises it for anything that isn't an `ErrorProfile`, and
    /// ``usernameSubmission(_:minimum:onAddMoney:)`` for the `ErrorProfile` cases
    /// the flow doesn't model. One string, one test.
    ///
    /// The only dialog in this file that stays destructive. The named rejections
    /// are things the user can fix by typing something else; this one means the
    /// claim did not go through and nobody knows why, which is worth both the
    /// red banner and the analytics event `.error` reports.
    static var usernameGenericFailure: DialogItem {
        .error(title: "Couldn't Save Your Username", subtitle: "Try again")
    }

    /// The balance gate (node 9442:103290). Names the server's minimum rather
    /// than a constant — the number is a flag, and the copy has to track it.
    static func usernameMinimumBalance(minimum: FiatAmount, onAddMoney: @escaping () -> Void) -> DialogItem {
        // Whole amounts read as "$100", not "$100.00" — this is a threshold
        // being quoted, not a balance being reported.
        let amount = minimum.formatted(minimumFractionDigits: 0)

        return .info(
            title: "\(amount) Minimum Balance Required",
            subtitle: "In order to stop username squatting getting a username requires a total Flipcash balance of at least \(amount) \(minimum.currency.rawValue.uppercased())"
        ) {
            .standard("Add Money", action: onAddMoney);
            .dismiss(kind: .subtle)
        }
    }

    /// The three client-side rejections (nodes 9442:5392, 9442:5257,
    /// 9442:5122). Raised on Next rather than blocked at the keystroke, so the
    /// user is told which rule they broke.
    ///
    /// Informational, not destructive: the designer drew all five rejections on
    /// the grey banner. A handle that is two characters short is a correction to
    /// make, not a failure to report.
    static func usernameValidation(_ failure: UsernameValidator.Failure) -> DialogItem {
        switch failure {
        case .tooShort:
            .info(
                title: "Too Short",
                subtitle: "Usernames must be a minimum of \(UsernameValidator.minimumLength) characters"
            )
        case .tooLong:
            .info(
                title: "Too Long",
                subtitle: "Usernames must be a maximum of \(UsernameValidator.maximumLength) characters"
            )
        case .invalidCharacters:
            .info(
                title: "Invalid Characters",
                subtitle: "Only letters, numbers, and underscores are allowed"
            )
        }
    }

    /// The server's rejections, all on the grey banner for the reason given on
    /// ``usernameValidation(_:)``. `minimum` is the same flag the entry-point
    /// gate reads: an `insufficientBalance` that got past the gate — a stale balance,
    /// or a rule the client doesn't model — lands back on the gate's own dialog
    /// rather than on a seventh error.
    static func usernameSubmission(
        _ error: ErrorProfile,
        minimum: FiatAmount?,
        onAddMoney: @escaping () -> Void
    ) -> DialogItem {
        // Anything the client doesn't model lands here, including an
        // `insufficientBalance` raised before user flags carried a minimum.
        let generic = DialogItem.usernameGenericFailure

        switch error {
        case .usernameTaken:
            return .info(title: "Username Taken", subtitle: "Please try a different username")

        case .reservedWord:
            return .info(
                title: "Trademarks Not Allowed",
                subtitle: "Please pick a different name that is not trademarked. If you own the trademark please contact support@flipcash.com"
            )

        case .moderated:
            // Subtitle copied from `ProfileNameScreen`'s moderation dialog, per
            // the designer's "(Please copy from display name error text)".
            return .info(title: "Inappropriate Username", subtitle: "Try a different name")

        case .invalidUsername:
            return .info(title: "This Username Isn't Valid", subtitle: "Try a different name")

        case .insufficientBalance:
            guard let minimum else { return generic }
            return .usernameMinimumBalance(minimum: minimum, onAddMoney: onAddMoney)

        // Everything the username flow doesn't model. Listed rather than
        // defaulted so a new `ErrorProfile` case has to be considered here
        // instead of silently inheriting "try again" — `.denied` in particular
        // is a real `SetUsername` rejection that is only here because it has no
        // signed-off copy yet.
        case .denied, .invalidDisplayName, .blobNotFound, .blobNotReady, .blobRejected, .invalidBlob, .network, .unknown:
            return generic
        }
    }

    /// The lookup screen's miss (node 9442:103386). Informational for the same
    /// reason the claim screen's rejections are: nobody has claimed this handle
    /// is an answer, not a fault, and the user fixes it by typing something else.
    ///
    /// Deliberately different copy from the tip card's `No Such Account` /
    /// `Nobody has claimed @x`. That one is reached by following someone's link,
    /// where naming the handle back is what explains the dead end; here the
    /// handle is still in the field the user is looking at.
    static var usernameNotFound: DialogItem {
        .info(title: "Username Not Found", subtitle: "Please try a different username")
    }

    /// A lookup that never got an answer. Keeps the red banner and the apology,
    /// because unlike a miss this one is worth retrying.
    static var usernameLookupFailure: DialogItem {
        .error(
            title: "Couldn't Look Up Username",
            subtitle: "Please check your connection and try again"
        )
    }

    /// Which of the two a thrown lookup gets. `ProfileService` turns the
    /// server's own `notFound` into `Profile.empty` rather than a throw, so the
    /// caller detects a miss from the result and this mapper mostly answers
    /// with the failure. It maps `.notFound` anyway, because the alternative if
    /// that ever changes is telling the user their connection is broken.
    static func usernameLookup(for error: Error) -> DialogItem {
        guard let error = error as? ErrorFetchProfile else { return .usernameLookupFailure }
        switch error {
        case .notFound:
            return .usernameNotFound
        case .ok, .unknown, .transportFailure, .cancelled, .rejected:
            return .usernameLookupFailure
        }
    }
}
