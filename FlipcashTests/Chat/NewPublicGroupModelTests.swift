//
//  NewPublicGroupModelTests.swift
//  FlipcashTests
//

import Foundation
import UIKit
import Testing
@testable import Flipcash
import FlipcashCore
import FlipcashStore

@MainActor
@Suite("New public group form")
struct NewPublicGroupModelTests {

    // MARK: - Doubles -

    /// Records what the form asked of the server, and answers with whatever the test set.
    private final class SpyCreator: GroupChatCreating {

        private(set) var startChatCalls: [(title: String, blobID: BlobID?, rules: ConversationRules?, key: UUID)] = []
        private(set) var storeBlobCallCount = 0
        private(set) var finalizationCallCount = 0

        /// Thrown by the next `startChat`, then cleared — so a test can fail one attempt and let
        /// the retry through.
        var nextStartChatError: Error?
        /// Thrown by the next `awaitBlobFinalization`, then cleared.
        var nextFinalizationError: Error?

        func storeBlob(_ data: Data, mimeType: String) async throws -> BlobID {
            storeBlobCallCount += 1
            return BlobID(data: Data(repeating: UInt8(storeBlobCallCount), count: 32))
        }

        func awaitBlobFinalization(blobID: BlobID) async throws {
            finalizationCallCount += 1
            if let error = nextFinalizationError {
                nextFinalizationError = nil
                throw error
            }
        }

        func startChat(
            title: String,
            pictureBlobID: BlobID?,
            rules: ConversationRules?,
            idempotencyKey: UUID
        ) async throws -> Conversation {
            startChatCalls.append((title, pictureBlobID, rules, idempotencyKey))
            if let error = nextStartChatError {
                nextStartChatError = nil
                throw error
            }
            return Conversation(
                id: .test(7),
                members: [],
                lastMessage: nil,
                lastActivity: Date(),
                type: .group,
                title: title,
                rules: rules
            )
        }
    }

    /// Stands in for `Session`: a single USDF holding worth `usd`.
    private final class StubHoldings: ConversationGateReading {
        var isStaff = false
        var totalBalance: ExchangedFiat
        var holding: StoredBalance?

        init(usd: Decimal) {
            totalBalance = ExchangedFiat(nativeAmount: .usd(usd), rate: Rate(fx: 1, currency: .usd))
            holding = try? StoredBalance(
                quarks: NSDecimalNumber(decimal: usd * 1_000_000).uint64Value,
                symbol: "USDF",
                name: "USDF Coin",
                supplyFromBonding: nil,
                sellFeeBps: nil,
                mint: .usdf,
                vmAuthority: nil,
                updatedAt: Date(),
                imageURL: nil,
                costBasis: 0
            )
        }

        func balance(for mint: PublicKey) -> StoredBalance? {
            mint == .usdf ? holding : nil
        }
    }

    private let noRates: [CurrencyCode: Rate] = [:]

    /// A form filled in exactly as far as Create being enabled requires.
    private func filledModel(minimum: Decimal = 100) -> NewPublicGroupModel {
        let model = NewPublicGroupModel()
        model.title = "BadBoys"
        model.select(balance: .makeTest(mint: .usdf, quarks: 1_000_000))
        model.select(minimumBalance: .usd(minimum))
        return model
    }

    // MARK: - The custom-amount chip -

    @Test("The custom chip is unselected until a custom amount is set")
    func customChipStartsUnselected() {
        let model = NewPublicGroupModel()

        #expect(model.customMinimumBalance == nil)
    }

    @Test("A preset leaves the custom chip unselected")
    func presetLeavesCustomChipUnselected() {
        let model = NewPublicGroupModel()

        model.select(minimumBalance: .usd(10))

        #expect(model.customMinimumBalance == nil)
    }

    @Test("An off-preset amount selects the custom chip")
    func offPresetAmountSelectsCustomChip() {
        let model = NewPublicGroupModel()

        model.select(minimumBalance: .usd(37))

        #expect(model.customMinimumBalance == .usd(37))
    }

    @Test("Tapping a preset after a custom amount hands the chip back its ellipsis")
    func presetAfterCustomAmountClearsTheChip() {
        let model = NewPublicGroupModel()
        model.select(minimumBalance: .usd(37))

        model.select(minimumBalance: .usd(10))

        // Nil is what the chip draws its ellipsis for, so the two chips can't both read as
        // selected.
        #expect(model.customMinimumBalance == nil)
        #expect(model.minimumBalance == .usd(10))
    }

    @Test("A custom amount typed to a preset's figure counts as that preset")
    func customAmountMatchingAPresetSelectsThePreset() {
        let model = NewPublicGroupModel()

        // The sheet hands back USD, so an entry worth exactly $50 is the $50 preset — one chip
        // lights, and it is that one.
        model.select(minimumBalance: .usd(50))

        #expect(model.customMinimumBalance == nil)
    }

    // MARK: - The mint the form opens on -

    @Test("The mint the form opens on is seated but not counted as chosen")
    func seededMintIsNotAChoice() {
        let model = NewPublicGroupModel()

        model.seed(balance: .makeTest(mint: .usdf))

        // The heading turns on this, not on the mint: node 10127:118014 names a mint and still
        // reads "Minimum Balance Required".
        #expect(model.selectedBalance?.stored.mint == .usdf)
        #expect(model.hasChosenMint == false)
    }

    @Test("Picking the mint the form opened on still counts as choosing it")
    func choosingTheSeededMintCounts() {
        let model = NewPublicGroupModel()
        model.seed(balance: .makeTest(mint: .usdf))

        model.select(balance: .makeTest(mint: .usdf))

        #expect(model.hasChosenMint)
    }

    @Test("Seeding never walks over the mint the user picked")
    func seedLeavesAChoiceAlone() {
        let model = NewPublicGroupModel()
        model.select(balance: .makeTest(mint: .jeffy))

        // Balances can land after the form is on screen, so a seed can arrive after a pick.
        model.seed(balance: .makeTest(mint: .usdf))

        #expect(model.selectedBalance?.stored.mint == .jeffy)
        #expect(model.hasChosenMint)
    }

    @Test("A wallet holding nothing giveable opens on no mint at all")
    func seedingNothingLeavesTheSlotEmpty() {
        let model = NewPublicGroupModel()

        model.seed(balance: nil)

        #expect(model.selectedBalance == nil)
        #expect(model.hasChosenMint == false)
        #expect(model.rules == nil, "Nothing to weigh the requirement in")
    }

    // MARK: - Rules -

    @Test("The requirement maps to a single listener rule naming exactly the selected mint")
    func rulesCarryOneListenerRequirementForTheSelectedMint() {
        let model = filledModel()

        // The contract caps the mint list at one entry, and an empty list means something else —
        // the requirement applying across every mint.
        #expect(model.rules == ConversationRules(
            listener: [.minimumBalance(MinimumBalanceRequirement(amount: .usd(100), mints: [.usdf]))]
        ))
        // Speaker is left unset: anyone who can read can send.
        #expect(model.rules?.speaker.isEmpty == true)
    }

    @Test("The rules stay nil until both halves of the requirement are collected")
    func rulesNilWhileRequirementIncomplete() {
        let model = NewPublicGroupModel()
        model.title = "BadBoys"
        #expect(model.rules == nil)

        model.select(minimumBalance: .usd(100))
        #expect(model.rules == nil, "An amount with no mint names nothing to weigh")

        model.select(balance: .makeTest(mint: .usdf))
        #expect(model.rules != nil)
    }

    // MARK: - The creator's own balance -

    @Test("Create stays disabled while the creator is short of the bar they drew")
    func createDisabledWhenCreatorIsShort() {
        let model = filledModel(minimum: 100)
        let short = StubHoldings(usd: 99)

        #expect(model.satisfiesOwnRules(session: short, rates: noRates) == false)
        #expect(model.canCreate(session: short, rates: noRates) == false)
    }

    @Test("Create is enabled once the creator clears their own requirement")
    func createEnabledWhenCreatorClearsTheBar() {
        let model = filledModel(minimum: 100)
        #expect(model.canCreate(session: StubHoldings(usd: 100), rates: noRates))
    }

    @Test("A title the validator rejects keeps Create disabled however healthy the balance is")
    func createDisabledWithoutAValidTitle() {
        let model = filledModel(minimum: 10)
        model.title = "   "
        #expect(model.validatedTitle == nil)
        #expect(model.canCreate(session: StubHoldings(usd: 10_000), rates: noRates) == false)
    }

    @Test("An incomplete requirement keeps Create disabled")
    func createDisabledWithoutARequirement() {
        let model = NewPublicGroupModel()
        model.title = "BadBoys"
        #expect(model.canCreate(session: StubHoldings(usd: 10_000), rates: noRates) == false)
    }

    // MARK: - Idempotency key -

    @Test("Every retry of one Create attempt carries the key the first attempt minted")
    func retriesReuseTheFirstAttemptsKey() async throws {
        let model = filledModel()
        let creator = SpyCreator()

        creator.nextStartChatError = ErrorStartChat.transportFailure
        await #expect(throws: ErrorStartChat.self) { try await model.create(using: creator) }

        _ = try await model.create(using: creator)

        #expect(creator.startChatCalls.count == 2)
        #expect(creator.startChatCalls[0].key == creator.startChatCalls[1].key)
        #expect(model.attemptKey == creator.startChatCalls[0].key)
    }

    @Test("An edited retry keeps the key, so the server answers with the chat the first call bound")
    func editedRetryKeepsTheKey() async throws {
        let model = filledModel()
        let creator = SpyCreator()

        creator.nextStartChatError = ErrorStartChat.transportFailure
        await #expect(throws: ErrorStartChat.self) { try await model.create(using: creator) }

        // Parameters are not part of the chat's identity — the caller and the key are — so an
        // edit must not mint a new one.
        model.title = "BadBoys Reloaded"
        _ = try await model.create(using: creator)

        #expect(creator.startChatCalls[0].key == creator.startChatCalls[1].key)
        #expect(creator.startChatCalls[1].title == "BadBoys Reloaded")
    }

    @Test("The key is minted at the first Create tap, not before")
    func keyIsNotMintedWhileTheFormIsFilledIn() async throws {
        let model = filledModel()
        #expect(model.attemptKey == nil)

        _ = try await model.create(using: SpyCreator())
        #expect(model.attemptKey != nil)
    }

    // MARK: - Submission -

    @Test("Create submits the validated title and the mapped rules")
    func createSubmitsValidatedTitleAndRules() async throws {
        let model = filledModel()
        model.title = "  BadBoys  "
        let creator = SpyCreator()

        let conversation = try await model.create(using: creator)

        #expect(creator.startChatCalls.first?.title == "BadBoys")
        #expect(creator.startChatCalls.first?.rules == model.rules)
        #expect(creator.startChatCalls.first?.blobID == nil, "A group with no picture carries no blob")
        #expect(conversation.type == .group)
    }

    @Test("Create against an incomplete form throws rather than calling the server")
    func createOnIncompleteFormThrows() async {
        let model = NewPublicGroupModel()
        let creator = SpyCreator()

        await #expect(throws: NewPublicGroupIncomplete.self) { try await model.create(using: creator) }
        #expect(creator.startChatCalls.isEmpty)
    }

    @Test("A rejected picture clears the reservation so a different one starts clean")
    func rejectedPictureClearsTheReservation() async throws {
        let model = filledModel()
        model.select(picture: UIImage.solid(.red))
        let creator = SpyCreator()

        creator.nextFinalizationError = ErrorBlob.rejected(.moderation)
        await #expect(throws: ErrorBlob.self) { try await model.create(using: creator) }
        #expect(model.reservedBlobID == nil)
        #expect(creator.startChatCalls.isEmpty, "A picture the server refused never reaches StartChat")

        _ = try await model.create(using: creator)
        #expect(creator.storeBlobCallCount == 2, "A cleared reservation re-stores")
    }

    @Test("A picture the server accepted is stored once and reused across retries")
    func acceptedPictureIsStoredOnce() async throws {
        let model = filledModel()
        model.select(picture: UIImage.solid(.blue))
        let creator = SpyCreator()

        creator.nextStartChatError = ErrorStartChat.transportFailure
        await #expect(throws: ErrorStartChat.self) { try await model.create(using: creator) }
        _ = try await model.create(using: creator)

        // The reservation signs the byte count, so re-encoding would store a second copy of a
        // picture the server already holds.
        #expect(creator.storeBlobCallCount == 1)
        #expect(creator.startChatCalls[0].blobID == creator.startChatCalls[1].blobID)
    }
}

private extension UIImage {
    /// A 16×16 fill, small enough that the encoder never has to downscale it.
    static func solid(_ color: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16)).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        }
    }
}
