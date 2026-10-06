//
//  EditBioModel.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

private let logger = Logger(label: "flipcash.edit-bio")

/// The bio editor's state and its one save.
///
/// The calls are injected: `FlipClient` is a concrete class with a live gRPC channel, so a test
/// has nothing to fake.
@MainActor
@Observable
final class EditBioModel {

    /// What the server refused the bio for, shown under the field. Cleared by the next edit.
    enum FieldError: Equatable {
        case moderated
        case invalid

        var message: String {
            switch self {
            case .moderated: "This bio isn't allowed. Try different wording"
            case .invalid:   "This bio isn't valid"
            }
        }
    }

    /// Where the save is. `.saved` is held by the screen for its checkmark before it pops.
    enum SaveState: Equatable {
        case normal
        case saving
        case saved
    }

    static let maxLength = 160

    /// The bio as typed. Editing it clears ``fieldError``.
    var text: String {
        didSet {
            guard text != oldValue else { return }
            fieldError = nil
        }
    }

    private(set) var state: SaveState = .normal
    private(set) var fieldError: FieldError?

    /// A failure with no field to blame, shown as a dialog. Set to nil once shown.
    var failure: Error?

    @ObservationIgnored private let initialText: String
    @ObservationIgnored private let validator = LengthValidator(maxLength: maxLength)
    @ObservationIgnored private let saving: (String) async throws -> Void
    @ObservationIgnored private let refresh: () async throws -> Void

    /// - Parameters:
    ///   - bio: the bio the profile carries now.
    ///   - saving: submits the trimmed bio.
    ///   - refresh: re-reads the profile so the rest of the app sees the new bio.
    init(
        bio: String,
        saving: @escaping (String) async throws -> Void,
        refresh: @escaping () async throws -> Void
    ) {
        self.text = bio
        self.initialText = bio
        self.saving = saving
        self.refresh = refresh
    }

    /// How many more characters fit, negative once over the limit.
    var remaining: Int {
        Self.maxLength - text.count
    }

    /// Whether Save is enabled. Clearing the bio to empty is a change like any other.
    var canSave: Bool {
        state == .normal && submission != nil && submission != Self.trim(initialText)
    }

    /// The bio as it would be submitted, or nil while it is over the limit. Empty is valid, unlike
    /// for `LengthValidator`, which rejects blank input: clearing the bio is an edit.
    private var submission: String? {
        let trimmed = Self.trim(text)
        return trimmed.isEmpty ? trimmed : validator.validate(trimmed)
    }

    private static func trim(_ string: String) -> String {
        string.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Submits the bio, then re-reads the profile. Failures land in ``fieldError`` or ``failure``.
    func save() async {
        guard canSave, let submission else { return }

        state = .saving
        fieldError = nil

        do {
            try await saving(submission)
            try await refresh()
            state = .saved

        } catch ErrorProfile.moderated(let category) {
            state = .normal
            logger.info("Bio moderation denied", metadata: ["category": "\(category)"])
            fieldError = .moderated

        } catch ErrorProfile.invalidBio {
            state = .normal
            logger.info("Bio rejected as invalid")
            fieldError = .invalid

        } catch {
            state = .normal
            guard !Task.isCancelled else { return }
            logger.error("Failed to set bio", metadata: ["error": "\(error)"])
            ErrorReporting.captureError(error, reason: "Failed to set bio")
            failure = error
        }
    }
}
