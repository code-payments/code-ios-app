//
//  EditGroupDescriptionModel.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

private let logger = Logger(label: "flipcash.edit-group-description")

/// The group description editor's state and its one save. Modelled on ``EditBioModel``.
///
/// The call is injected: `FlipClient` is a concrete class with a live gRPC channel, so a test has
/// nothing to fake.
@MainActor
@Observable
final class EditGroupDescriptionModel {

    /// What the server refused the description for, shown under the field. Cleared by the next edit.
    enum FieldError: Equatable {
        case moderated

        var message: String {
            switch self {
            case .moderated: "This description isn't allowed. Try different wording"
            }
        }
    }

    /// Where the save is. `.saved` is held by the screen for its checkmark before it pops.
    enum SaveState: Equatable {
        case normal
        case saving
        case saved
    }

    /// `EditChatRequest.Description.value`'s `max_len`.
    static let maxLength = 160

    /// The description as typed. Editing it clears ``fieldError``.
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
    @ObservationIgnored private let saving: (ConversationDescriptionEdit) async throws -> Void

    /// - Parameters:
    ///   - description: the description the group carries now.
    ///   - saving: submits the edit and seats the chat's post-edit metadata.
    init(
        description: String,
        saving: @escaping (ConversationDescriptionEdit) async throws -> Void
    ) {
        self.text = description
        self.initialText = description
        self.saving = saving
    }

    /// How many more characters fit, negative once over the limit.
    var remaining: Int {
        Self.maxLength - text.count
    }

    /// Whether Save is enabled. Clearing the description to empty is a change like any other.
    var canSave: Bool {
        state == .normal && submission != nil && submission != Self.trim(initialText)
    }

    /// The description as it would be submitted, or nil while it is over the limit. Empty is valid,
    /// unlike for `LengthValidator`, which rejects blank input: clearing it is an edit.
    private var submission: String? {
        let trimmed = Self.trim(text)
        return trimmed.isEmpty ? trimmed : validator.validate(trimmed)
    }

    private static func trim(_ string: String) -> String {
        string.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Submits the description, as a clear when it is empty. Failures land in ``fieldError`` or
    /// ``failure``.
    func save() async {
        guard canSave, let submission else { return }

        state = .saving
        fieldError = nil

        do {
            try await saving(submission.isEmpty ? .clear : .set(submission))
            state = .saved

        } catch ErrorEditChat.descriptionModerated(let category) {
            state = .normal
            logger.info("Group description moderation denied", metadata: ["category": "\(category)"])
            fieldError = .moderated

        } catch {
            state = .normal
            guard !Task.isCancelled else { return }
            logger.error("Failed to set group description", metadata: ["error": "\(error)"])
            ErrorReporting.captureError(error, reason: "Failed to set group description")
            failure = error
        }
    }
}
