//
//  NewPublicGroupModel.swift
//  Flipcash
//

import UIKit
import FlipcashCore

/// Thrown when Create runs against an incomplete form. The button is disabled in that state, so
/// this is a programming error rather than something the screen puts in front of the user.
struct NewPublicGroupIncomplete: Error {}

/// Everything the "New Public Group" form holds while it is being filled in, and the one call that
/// submits it (node 10127:118014).
///
/// The balance requirement is denominated in USD. The presets the design offers are dollar amounts
/// and `StoredBalance.usdf` — the holding's USD worth, resolved at store time — is what the gate
/// weighs them against, so USD is the one denomination that needs no rate to enforce.
@MainActor
@Observable
final class NewPublicGroupModel {

    /// The title as typed. Submitted through ``GroupTitleValidator``, never raw.
    var title: String = ""

    /// The picture the user picked, before it is encoded or uploaded. Optional — the contract
    /// leaves the blob unset for a group with no picture.
    private(set) var picture: UIImage?

    /// Which holdings count toward the requirement. Opens on ``CurrencyChoice/all``, the rule every
    /// creator can draw without first having to pick a token.
    private(set) var currency: CurrencyChoice = .all

    /// The minimum balance a member must hold, in USD.
    private(set) var minimumBalance: FiatAmount?

    /// Whether a create is in flight, so the button stops taking taps.
    private(set) var isCreating = false

    /// The key identifying this create attempt, minted when the user first taps Create and held
    /// for every retry after.
    ///
    /// The server derives the chat's identity from the caller and this key, so a retry carrying a
    /// key an earlier call already used returns the chat that call created rather than making a
    /// second one — which is the whole point, since a response lost on the way back leaves the
    /// client unable to tell a failed call from a successful one. A key minted at the call site
    /// would be a fresh key on every retry and would buy nothing.
    ///
    /// Never reset. An attempt the server rejected bound no chat to the key, so carrying it into
    /// an edited retry is both safe and what protects the one case that matters.
    private(set) var attemptKey: UUID?

    /// The blob the picture landed in, held across retries for the reason ``attemptKey`` is: the
    /// reservation signs the byte count, so a retry that re-encoded would be storing a second copy
    /// of a picture the server already has.
    private(set) var reservedBlobID: BlobID?

    /// The dollar amounts the form offers as one tap each, before the custom entry (node
    /// 10127:118014).
    static let presets: [FiatAmount] = [.usd(10), .usd(50), .usd(100)]

    /// Cap on the encoded picture, matching the profile photo's.
    private static let maxUploadBytes = 2 * 1_024 * 1_024

    private let validator = GroupTitleValidator()

    init() {}

    // MARK: - Form state -

    func select(picture: UIImage) {
        self.picture = picture
    }

    func select(balance: ExchangedBalance) {
        currency = .specific(balance)
    }

    func selectAllCurrencies() {
        currency = .all
    }

    func select(minimumBalance: FiatAmount) {
        self.minimumBalance = minimumBalance
    }

    /// The requirement when it is not one of ``presets`` — what the form's fourth chip wears in
    /// place of its ellipsis, and the only state that chip reads as selected.
    ///
    /// Nil while nothing is set and again the moment a preset is picked, so a custom amount
    /// followed by a tap on $10 hands the chip back its ellipsis rather than leaving two chips lit.
    var customMinimumBalance: FiatAmount? {
        guard let minimumBalance, !Self.presets.contains(minimumBalance) else { return nil }
        return minimumBalance
    }

    /// The title as it would be submitted, or nil while the form holds nothing the server accepts.
    var validatedTitle: String? {
        validator.validate(title)
    }

    /// How many more Unicode scalars the title field accepts.
    var remainingTitleScalars: Int {
        validator.remaining(in: title)
    }

    /// The rules the chat is created with, or nil while no amount has been picked.
    ///
    /// Only a listener requirement is set: it is the one the design collects, and the contract
    /// applies speaker rules on top of listener rules, so leaving `speaker` unset means "anyone who
    /// can read can send".
    var rules: ConversationRules? {
        guard let minimumBalance else { return nil }
        return Self.rules(minimumBalance: minimumBalance, currency: currency)
    }

    /// Whether the user's holdings added together clear the amount picked, whatever
    /// ``currency`` is — what the picker's All Currencies card states. True while no amount is
    /// picked.
    func satisfiesAllCurrencies(session: some ConversationGateReading, rates: [CurrencyCode: Rate]) -> Bool {
        let rules = minimumBalance.map { Self.rules(minimumBalance: $0, currency: .all) }
        return conversationGate(session: session, rules: rules, rates: rates).listener.isSatisfied
    }

    /// The contract caps the mint list at one entry, and an empty list is the requirement applying
    /// to every holding added together, USDF included.
    private static func rules(minimumBalance: FiatAmount, currency: CurrencyChoice) -> ConversationRules {
        ConversationRules(
            listener: [.minimumBalance(MinimumBalanceRequirement(
                amount: minimumBalance,
                mints: currency.mint.map { [$0] } ?? []
            ))]
        )
    }

    /// Whether the user clears the bar they just drew.
    ///
    /// Run through the same evaluator the join gate uses rather than a second balance comparison:
    /// the server refuses a `StartChat` whose caller doesn't satisfy its own rules
    /// (`RULES_NOT_SATISFIED`), and one copy of the rule is the only way the button and the server
    /// can't disagree. True while the requirement is incomplete — there is nothing to fall short of
    /// yet, and ``canCreate(session:rates:)`` gates on the requirement separately.
    func satisfiesOwnRules(session: some ConversationGateReading, rates: [CurrencyCode: Rate]) -> Bool {
        conversationGate(session: session, rules: rules, rates: rates).listener.isSatisfied
    }

    /// Whether Create is enabled: a title the server will take, a requirement the form has finished
    /// collecting, the creator clearing it, and nothing already in flight.
    func canCreate(session: some ConversationGateReading, rates: [CurrencyCode: Rate]) -> Bool {
        guard !isCreating, validatedTitle != nil, rules != nil else { return false }
        return satisfiesOwnRules(session: session, rates: rates)
    }

    // MARK: - Create -

    /// Uploads the picture if there is one, then creates the chat, and returns it.
    ///
    /// Throws `ErrorStartChat` for every server result the screen has copy for, `ErrorBlob` when
    /// the picture is refused, and ``NewPublicGroupIncomplete`` when called against a form Create
    /// should have been disabled for.
    func create(using creator: some GroupChatCreating) async throws -> Conversation {
        guard let title = validatedTitle, let rules else {
            throw NewPublicGroupIncomplete()
        }

        isCreating = true
        defer { isCreating = false }

        let key = attemptKey ?? UUID()
        attemptKey = key

        let blobID = try await uploadPictureIfNeeded(using: creator)

        do {
            let conversation = try await creator.startChat(
                title: title,
                pictureBlobID: blobID,
                rules: rules,
                idempotencyKey: key
            )
            Analytics.groupCreated(error: nil, rules: rules, hasPicture: blobID != nil)
            return conversation
        } catch {
            Analytics.groupCreated(error: error, rules: rules, hasPicture: blobID != nil)
            throw error
        }
    }

    /// Stores and finalizes the picture, returning the blob `StartChat` should carry, or nil when
    /// the group has no picture. A rejected blob clears the reservation so a different picture
    /// starts clean.
    private func uploadPictureIfNeeded(using creator: some GroupChatCreating) async throws -> BlobID? {
        if reservedBlobID == nil, let picture {
            // Encode before storing: the reservation signs the byte count, so the bytes may not
            // change afterwards.
            let data = try await ImageEncoder.encodeForUpload(picture, maxBytes: Self.maxUploadBytes)
            reservedBlobID = try await creator.storeBlob(data, mimeType: "image/jpeg")
        }

        guard let blobID = reservedBlobID else { return nil }

        do {
            try await creator.awaitBlobFinalization(blobID: blobID)
        } catch ErrorBlob.rejected(let reason) {
            reservedBlobID = nil
            throw ErrorBlob.rejected(reason)
        }

        return blobID
    }
}

extension NewPublicGroupModel {

    /// The holdings a group's balance requirement counts.
    enum CurrencyChoice: Equatable {
        /// Every holding added together.
        case all
        /// One holding, kept whole so the form's row can draw the token's name and icon. Only
        /// ``ExchangedBalance/stored``'s mint reaches the wire.
        case specific(ExchangedBalance)

        /// The mint of the chosen holding, or nil when every holding counts.
        var mint: PublicKey? {
            switch self {
            case .all:                   return nil
            case .specific(let balance): return balance.stored.mint
            }
        }
    }
}
