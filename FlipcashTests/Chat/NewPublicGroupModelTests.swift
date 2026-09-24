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

    /// Stands in for `Session`: a USDF holding worth `usd`, plus `otherUSD` held in other mints and
    /// counted only in the total.
    private final class StubHoldings: ConversationGateReading {
        var isStaff = false
        var totalBalance: ExchangedFiat
        var holding: StoredBalance?

        init(usd: Decimal, otherUSD: Decimal = 0) {
            totalBalance = ExchangedFiat(nativeAmount: .usd(usd + otherUSD), rate: Rate(fx: 1, currency: .usd))
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

    // MARK: - Currency choice -

    @Test("The form opens on All Currencies")
    func opensOnAllCurrencies() {
        let model = NewPublicGroupModel()

        #expect(model.currency == .all)
        #expect(model.currency.mint == nil, "No token row reads as selected in the picker")
    }

    @Test("Picking a token replaces All Currencies")
    func pickingATokenReplacesAll() {
        let model = NewPublicGroupModel()

        model.select(balance: .makeTest(mint: .jeffy))

        #expect(model.currency != .all)
        #expect(model.currency.mint == .jeffy)
    }

    @Test("Choosing All Currencies after a token clears the token")
    func choosingAllClearsTheToken() {
        let model = NewPublicGroupModel()
        model.select(balance: .makeTest(mint: .jeffy))

        model.selectAllCurrencies()

        #expect(model.currency == .all)
        #expect(model.currency.mint == nil)
    }

    // MARK: - Rules -

    @Test("All Currencies maps to a requirement with no mints")
    func allCurrenciesRulesCarryNoMints() {
        let model = NewPublicGroupModel()
        model.select(minimumBalance: .usd(100))

        // An empty mint list is the requirement applying to every holding added together.
        #expect(model.rules == ConversationRules(
            listener: [.minimumBalance(MinimumBalanceRequirement(amount: .usd(100), mints: []))]
        ))
        #expect(model.rules?.speaker.isEmpty == true)
    }

    @Test("A picked token maps to a requirement naming exactly that mint")
    func rulesCarryOneListenerRequirementForTheSelectedMint() {
        let model = filledModel()

        #expect(model.rules == ConversationRules(
            listener: [.minimumBalance(MinimumBalanceRequirement(amount: .usd(100), mints: [.usdf]))]
        ))
        // Speaker is left unset: anyone who can read can send.
        #expect(model.rules?.speaker.isEmpty == true)
    }

    @Test("Switching back to All Currencies drops the mint from the rules")
    func switchingBackToAllDropsTheMint() {
        let model = filledModel()

        model.selectAllCurrencies()

        #expect(model.rules == ConversationRules(
            listener: [.minimumBalance(MinimumBalanceRequirement(amount: .usd(100), mints: []))]
        ))
    }

    @Test("The rules stay nil until an amount is picked")
    func rulesNilWhileRequirementIncomplete() {
        let model = NewPublicGroupModel()
        model.title = "BadBoys"
        #expect(model.rules == nil)

        model.select(minimumBalance: .usd(100))
        #expect(model.rules != nil)
    }

    @Test("Create sends an All Currencies group with no mints")
    func createSendsEmptyMints() async throws {
        let model = NewPublicGroupModel()
        model.title = "Ballers"
        model.select(minimumBalance: .usd(100))
        let creator = SpyCreator()

        _ = try await model.create(using: creator)

        #expect(creator.startChatCalls.first?.rules == ConversationRules(
            listener: [.minimumBalance(MinimumBalanceRequirement(amount: .usd(100), mints: []))]
        ))
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

    @Test("All Currencies counts every holding toward the creator's own requirement")
    func allCurrenciesSumsTheCreatorsHoldings() {
        let model = NewPublicGroupModel()
        model.title = "Ballers"
        model.select(minimumBalance: .usd(100))

        // $40 of USDF alone is short; with $60 held elsewhere the total clears $100.
        let spread = StubHoldings(usd: 40, otherUSD: 60)

        #expect(model.satisfiesOwnRules(session: spread, rates: noRates))
        #expect(model.canCreate(session: spread, rates: noRates))
    }

    @Test("All Currencies stays short when the holdings added together are short")
    func allCurrenciesShortWhenTheTotalIsShort() {
        let model = NewPublicGroupModel()
        model.title = "Ballers"
        model.select(minimumBalance: .usd(100))

        let short = StubHoldings(usd: 40, otherUSD: 59)

        #expect(model.satisfiesOwnRules(session: short, rates: noRates) == false)
        #expect(model.canCreate(session: short, rates: noRates) == false)
    }

    @Test("A picked token weighs only that token, not the total")
    func specificTokenIgnoresOtherHoldings() {
        let model = filledModel(minimum: 100)
        let spread = StubHoldings(usd: 40, otherUSD: 60)

        #expect(model.satisfiesOwnRules(session: spread, rates: noRates) == false)
    }

    @Test("The All Currencies card weighs the total even while a token is picked")
    func allCurrenciesCardWeighsTheTotal() {
        let model = filledModel(minimum: 100)

        #expect(model.satisfiesAllCurrencies(session: StubHoldings(usd: 40, otherUSD: 60), rates: noRates))
        #expect(model.satisfiesAllCurrencies(session: StubHoldings(usd: 40, otherUSD: 59), rates: noRates) == false)
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
