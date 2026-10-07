//
//  ConversationGateTests.swift
//  FlipcashTests
//

import Foundation
import Testing
@testable import Flipcash
import FlipcashCore
import FlipcashStore

@MainActor
@Suite("Group chat participation gate")
struct ConversationGateTests {

    private typealias StubHoldings = StubGateHoldings

    private func holding(usd: Decimal) throws -> StoredBalance {
        try .usdfHolding(usd: usd)
    }

    private func minimumBalance(_ usd: Decimal, mints: [PublicKey] = []) -> MinimumBalanceRequirement {
        MinimumBalanceRequirement(amount: .usd(usd), mints: mints)
    }

    private let noRates: [CurrencyCode: Rate] = [:]

    // MARK: - No rules

    @Test("A chat with no rules is open to everyone")
    func noRules_open() {
        let gate = conversationGate(session: StubHoldings(), rules: nil, rates: noRates)
        #expect(gate == .open)
    }

    @Test("An empty rule set is open, matching the contract's 'if empty, anyone can'")
    func emptyRules_open() {
        let gate = conversationGate(session: StubHoldings(), rules: ConversationRules(), rates: noRates)
        #expect(gate == .open)
    }

    // MARK: - Staff

    @Test("A never speaker rule leaves everyone, staff included, unable to send")
    func neverSpeakerRule_unsatisfied() {
        let rules = ConversationRules(speaker: [.never])
        let gate = conversationGate(session: StubHoldings(isStaff: true), rules: rules, rates: noRates)
        #expect(gate.listener == .satisfied)
        #expect(gate.speaker == .unsatisfied(unmet: [.never], primary: .never))
    }

    @Test("A creator speaker rule is met by the chat's creator")
    func creatorSpeakerRule_creatorViewer_open() {
        let me = UUID()
        let rules = ConversationRules(speaker: [.creator])
        let gate = conversationGate(session: StubHoldings(userID: me), rules: rules, creator: me, rates: noRates)
        #expect(gate.isOpen)
        #expect(conversationGatePresentation(gate, isMember: true) == .open)
    }

    @Test("A creator speaker rule leaves a non-creator read-only")
    func creatorSpeakerRule_otherViewer_readOnly() {
        let rules = ConversationRules(speaker: [.creator])
        let gate = conversationGate(session: StubHoldings(), rules: rules, creator: UUID(), rates: noRates)
        #expect(gate.listener == .satisfied)
        #expect(gate.speaker == .unsatisfied(unmet: [.creator], primary: .creator))
        #expect(conversationGatePresentation(gate, isMember: true) == .readOnly(.creator))
    }

    @Test("Staff get no bypass of a creator speaker rule")
    func creatorSpeakerRule_staffNonCreator_readOnly() {
        let rules = ConversationRules(speaker: [.creator])
        let gate = conversationGate(session: StubHoldings(isStaff: true), rules: rules, creator: UUID(), rates: noRates)
        #expect(gate.speaker == .unsatisfied(unmet: [.creator], primary: .creator))
    }

    @Test("A creator speaker rule on a chat with an unknown creator fails closed")
    func creatorSpeakerRule_unknownCreator_readOnly() {
        let rules = ConversationRules(speaker: [.creator])
        let gate = conversationGate(session: StubHoldings(), rules: rules, creator: nil, rates: noRates)
        #expect(gate.speaker == .unsatisfied(unmet: [.creator], primary: .creator))
    }

    @Test("An unsupported speaker rule blocks posting for everyone, staff included")
    func unsupportedSpeakerRule_staffViewer_readOnly() {
        let rules = ConversationRules(speaker: [.unsupported])
        let gate = conversationGate(session: StubHoldings(isStaff: true), rules: rules, rates: noRates)
        #expect(gate.listener == .satisfied)
        #expect(gate.speaker == .unsatisfied(unmet: [.unsupported], primary: .unsupported))
        #expect(conversationGatePresentation(gate, isMember: true) == .readOnly(.unsupported))
    }

    @Test("A member failing only a creator or unsupported rule can react but cannot post", arguments: [ConversationSpeakerRule.creator, .unsupported])
    func postingOnlyRule_memberCanReactButNotPost(_ rule: ConversationSpeakerRule) {
        let gate = conversationGate(session: StubHoldings(isStaff: true), rules: ConversationRules(speaker: [rule]), creator: UUID(), rates: noRates)
        let access = ConversationLoadCoordinator.access(isMember: true, gate: gate)
        #expect(access.canReact)
        #expect(!access.canPost)
    }

    @Test("A never rule blocks reactions as well as posting")
    func neverRule_blocksReactionsAndPosting() {
        let gate = conversationGate(session: StubHoldings(isStaff: true), rules: ConversationRules(speaker: [.never]), rates: noRates)
        let access = ConversationLoadCoordinator.access(isMember: true, gate: gate)
        #expect(!access.canReact)
        #expect(!access.canPost)
    }

    @Test("An unmet minimum balance or staff rule blocks reactions as well as posting")
    func balanceAndStaffRules_blockReactionsAndPosting() {
        for rule in [ConversationSpeakerRule.minimumBalance(minimumBalance(100)), .staff] {
            let gate = conversationGate(session: StubHoldings(), rules: ConversationRules(speaker: [rule]), rates: noRates)
            let access = ConversationLoadCoordinator.access(isMember: true, gate: gate)
            #expect(!access.canReact)
            #expect(!access.canPost)
        }
    }

    @Test("Creator paired with an unmet staff rule keeps reactions blocked")
    func creatorWithUnmetStaff_blocksReactions() {
        let me = UUID()
        let rules = ConversationRules(speaker: [.creator, .staff])
        let gate = conversationGate(session: StubHoldings(userID: me), rules: rules, creator: me, rates: noRates)
        let access = ConversationLoadCoordinator.access(isMember: true, gate: gate)
        #expect(!access.canReact)
        #expect(!access.canPost)
    }

    @Test("Creator paired with an unmet staff rule still allows reactions once staff is met and the viewer is not the creator")
    func creatorWithMetStaff_nonCreatorCanReact() {
        let rules = ConversationRules(speaker: [.creator, .staff])
        let gate = conversationGate(session: StubHoldings(isStaff: true), rules: rules, creator: UUID(), rates: noRates)
        let access = ConversationLoadCoordinator.access(isMember: true, gate: gate)
        #expect(access.canReact)
        #expect(!access.canPost)
    }

    @Test("A non-member can neither react nor post, whatever the rules say")
    func nonMember_hasNoAccess() {
        let access = ConversationLoadCoordinator.access(isMember: false, gate: .open)
        #expect(!access.canReact)
        #expect(!access.canPost)
    }

    @Test("The creator can react and post")
    func creator_canReactAndPost() {
        let me = UUID()
        let gate = conversationGate(session: StubHoldings(userID: me), rules: ConversationRules(speaker: [.creator]), creator: me, rates: noRates)
        let access = ConversationLoadCoordinator.access(isMember: true, gate: gate)
        #expect(access.canReact)
        #expect(access.canPost)
    }

    @Test("A read-only presentation still leaves the transcript readable")
    func readOnlyPresentation_doesNotObscureTranscript() {
        #expect(ConversationGatePresentation.readOnly(.creator).obscuresTranscript == false)
        #expect(ConversationGatePresentation.readOnly(.unsupported).obscuresTranscript == false)
    }

    @Test("An open chat lets a cash link in it be collected")
    func cashCollectionBlock_open() {
        #expect(ConversationGatePresentation.open.cashCollectionBlock(allowsReactions: true) == nil)
    }

    @Test("A non-member is told to join before collecting")
    func cashCollectionBlock_join() {
        #expect(ConversationGatePresentation.join(nil).cashCollectionBlock(allowsReactions: false) == .notMember)
        #expect(ConversationGatePresentation.join(.staff).cashCollectionBlock(allowsReactions: false) == .notMember)
    }

    @Test("A broadcast chat's audience still collects what the creator posts")
    func cashCollectionBlock_creatorOnly_collects() {
        let gate = conversationGate(session: StubHoldings(), rules: ConversationRules(speaker: [.creator]), creator: UUID(), rates: noRates)
        #expect(gate.allowsReactions)
        #expect(conversationGatePresentation(gate, isMember: true).cashCollectionBlock(allowsReactions: gate.allowsReactions) == nil)
    }

    @Test("A member who can't chat can't collect", arguments: [ConversationSpeakerRule.never, .staff])
    func cashCollectionBlock_cannotChat(rule: ConversationSpeakerRule) {
        let gate = conversationGate(session: StubHoldings(), rules: ConversationRules(speaker: [rule]), rates: noRates)
        #expect(!gate.allowsReactions)
        #expect(conversationGatePresentation(gate, isMember: true).cashCollectionBlock(allowsReactions: gate.allowsReactions) == .cannotChat)
    }

    @Test("Unmet or unknown listener rules refuse a collect")
    func cashCollectionBlock_blockedOrUndetermined() {
        #expect(ConversationGatePresentation.blocked(.staff).cashCollectionBlock(allowsReactions: false) == .cannotChat)
        #expect(ConversationGatePresentation.undetermined.cashCollectionBlock(allowsReactions: true) == .cannotChat)
    }

    @Test("A staff member satisfies a staff-only chat")
    func staffRule_staffUser_satisfied() {
        let rules = ConversationRules(listener: [.staff])
        let gate = conversationGate(session: StubHoldings(isStaff: true), rules: rules, rates: noRates)
        #expect(gate.isOpen)
    }

    @Test("A non-staff user fails a staff-only chat")
    func staffRule_nonStaffUser_unsatisfied() {
        let rules = ConversationRules(listener: [.staff])
        let gate = conversationGate(session: StubHoldings(), rules: rules, rates: noRates)
        #expect(gate.listener == .unsatisfied(unmet: [.staff], primary: .staff))
    }

    // MARK: - Minimum balance, one mint

    @Test("A holding above the single-mint minimum satisfies it")
    func singleMint_above_satisfied() throws {
        let rules = ConversationRules(listener: [.minimumBalance(minimumBalance(100, mints: [.usdf]))])
        let session = StubHoldings(balances: [.usdf: try holding(usd: 101)])
        #expect(conversationGate(session: session, rules: rules, rates: noRates).isOpen)
    }

    @Test("A holding exactly at the single-mint minimum satisfies it")
    func singleMint_exactly_satisfied() throws {
        let rules = ConversationRules(listener: [.minimumBalance(minimumBalance(100, mints: [.usdf]))])
        let session = StubHoldings(balances: [.usdf: try holding(usd: 100)])
        #expect(conversationGate(session: session, rules: rules, rates: noRates).isOpen)
    }

    @Test("A holding below the single-mint minimum fails it, naming the mint")
    func singleMint_below_unsatisfied() throws {
        let rules = ConversationRules(listener: [.minimumBalance(minimumBalance(100, mints: [.usdf]))])
        let session = StubHoldings(balances: [.usdf: try holding(usd: 99)])
        let gate = conversationGate(session: session, rules: rules, rates: noRates)
        #expect(gate.listener.primaryRequirement == .minimumBalance(amount: .usd(100), mint: .usdf))
    }

    @Test("A holding a fraction of a cent short of the single-mint minimum satisfies it, as the wallet shows it")
    func singleMint_subCentShort_satisfied() throws {
        // A launchpad holding valued against a supply that lags the buy lands just under what was
        // paid; the wallet rounds it back to the requirement, and so does the gate.
        let rules = ConversationRules(listener: [.minimumBalance(minimumBalance(5, mints: [.usdf]))])
        let session = StubHoldings(balances: [.usdf: try holding(usd: 4.998)])
        #expect(conversationGate(session: session, rules: rules, rates: noRates).isOpen)
    }

    @Test("A holding cents short of the single-mint minimum still fails it")
    func singleMint_centsShort_unsatisfied() throws {
        let rules = ConversationRules(listener: [.minimumBalance(minimumBalance(5, mints: [.usdf]))])
        let session = StubHoldings(balances: [.usdf: try holding(usd: 4.98)])
        let gate = conversationGate(session: session, rules: rules, rates: noRates)
        #expect(gate.listener.primaryRequirement == .minimumBalance(amount: .usd(5), mint: .usdf))
    }

    @Test("Not holding the required mint at all is a zero balance, not a pass")
    func singleMint_notHeld_unsatisfied() {
        let rules = ConversationRules(listener: [.minimumBalance(minimumBalance(100, mints: [.usdf]))])
        // A cumulative balance well over the minimum must not rescue a
        // requirement that names one mint.
        let session = StubHoldings(totalUSD: 5_000)
        let gate = conversationGate(session: session, rules: rules, rates: noRates)
        #expect(gate.listener.primaryRequirement == .minimumBalance(amount: .usd(100), mint: .usdf))
    }

    @Test("A zero minimum on a mint the user doesn't hold still passes")
    func singleMint_zeroMinimum_satisfied() {
        let rules = ConversationRules(listener: [.minimumBalance(minimumBalance(0, mints: [.usdf]))])
        #expect(conversationGate(session: StubHoldings(), rules: rules, rates: noRates).isOpen)
    }

    // MARK: - Minimum balance, all mints

    @Test("An empty mint list measures the cumulative balance across every mint")
    func allMints_cumulativeAbove_satisfied() {
        let rules = ConversationRules(listener: [.minimumBalance(minimumBalance(50))])
        let session = StubHoldings(totalUSD: 50)
        #expect(conversationGate(session: session, rules: rules, rates: noRates).isOpen)
    }

    @Test("A cumulative balance below an all-mint minimum fails it, naming no mint")
    func allMints_cumulativeBelow_unsatisfied() {
        let rules = ConversationRules(listener: [.minimumBalance(minimumBalance(50))])
        let session = StubHoldings(totalUSD: 49.99)
        let gate = conversationGate(session: session, rules: rules, rates: noRates)
        #expect(gate.listener.primaryRequirement == .minimumBalance(amount: .usd(50), mint: nil))
    }

    @Test("A cumulative balance a fraction of a cent short of an all-mint minimum satisfies it")
    func allMints_subCentShort_satisfied() {
        let rules = ConversationRules(listener: [.minimumBalance(minimumBalance(5))])
        #expect(conversationGate(session: StubHoldings(totalUSD: 4.998), rules: rules, rates: noRates).isOpen)
    }

    @Test("A cumulative balance cents short of an all-mint minimum still fails it")
    func allMints_centsShort_unsatisfied() {
        let rules = ConversationRules(listener: [.minimumBalance(minimumBalance(5))])
        let gate = conversationGate(session: StubHoldings(totalUSD: 4.98), rules: rules, rates: noRates)
        #expect(gate.listener.primaryRequirement == .minimumBalance(amount: .usd(5), mint: nil))
    }

    // MARK: - Several rules

    @Test("One failing rule among several fails the class, reporting only what is unmet")
    func severalRules_onePasses_reportsOnlyTheFailure() {
        let rules = ConversationRules(listener: [
            .staff,
            .minimumBalance(minimumBalance(100)),
        ])
        let session = StubHoldings(isStaff: true, totalUSD: 10)
        let gate = conversationGate(session: session, rules: rules, rates: noRates)
        #expect(gate.listener == .unsatisfied(
            unmet: [.minimumBalance(amount: .usd(100), mint: nil)],
            primary: .minimumBalance(amount: .usd(100), mint: nil)
        ))
    }

    @Test("When both a staff rule and a balance rule fail, the balance is what the user is told")
    func severalRules_bothFail_balanceIsPrimary() {
        let rules = ConversationRules(listener: [
            .staff,
            .minimumBalance(minimumBalance(100)),
        ])
        let gate = conversationGate(session: StubHoldings(), rules: rules, rates: noRates)
        #expect(gate.listener == .unsatisfied(
            unmet: [.staff, .minimumBalance(amount: .usd(100), mint: nil)],
            primary: .minimumBalance(amount: .usd(100), mint: nil)
        ))
    }

    // MARK: - Currency conversion

    @Test("A requirement in another currency is compared at the cached rate")
    func foreignCurrency_withRate_comparesInUSD() {
        // 200 CAD at 2 CAD/USD is $100; a $99 balance is short of it.
        let requirement = MinimumBalanceRequirement(amount: FiatAmount(value: 200, currency: .cad))
        let rules = ConversationRules(listener: [.minimumBalance(requirement)])
        let rates: [CurrencyCode: Rate] = [.cad: Rate(fx: 2, currency: .cad)]

        #expect(conversationGate(session: StubHoldings(totalUSD: 99), rules: rules, rates: rates).listener.isSatisfied == false)
        #expect(conversationGate(session: StubHoldings(totalUSD: 100), rules: rules, rates: rates).isOpen)
    }

    @Test("A requirement in a currency with no cached rate fails open rather than locking the user out")
    func foreignCurrency_withoutRate_failsOpen() {
        let requirement = MinimumBalanceRequirement(amount: FiatAmount(value: 1_000_000, currency: .cad))
        let rules = ConversationRules(listener: [.minimumBalance(requirement)])
        #expect(conversationGate(session: StubHoldings(), rules: rules, rates: noRates).isOpen)
    }

    // MARK: - Speaker on top of listener

    @Test("A speaker rule is evaluated on its own once the listener rules pass")
    func speaker_listenerPasses_speakerFails() {
        let rules = ConversationRules(
            listener: [],
            speaker: [.minimumBalance(minimumBalance(100))]
        )
        let gate = conversationGate(session: StubHoldings(totalUSD: 10), rules: rules, rates: noRates)
        #expect(gate.listener == .satisfied)
        #expect(gate.speaker.primaryRequirement == .minimumBalance(amount: .usd(100), mint: nil))
    }

    @Test("A failing listener rule fails the speaker verdict too, carrying both rule sets")
    func speaker_listenerFails_speakerFailsWithBoth() {
        let rules = ConversationRules(
            listener: [.staff],
            speaker: [.minimumBalance(minimumBalance(100))]
        )
        let gate = conversationGate(session: StubHoldings(totalUSD: 10), rules: rules, rates: noRates)
        #expect(gate.speaker == .unsatisfied(
            unmet: [.staff, .minimumBalance(amount: .usd(100), mint: nil)],
            primary: .minimumBalance(amount: .usd(100), mint: nil)
        ))
    }

    @Test("No speaker rules means anyone who can listen can send")
    func speaker_noRules_satisfiedWithListener() {
        let rules = ConversationRules(listener: [.staff])
        let gate = conversationGate(session: StubHoldings(isStaff: true), rules: rules, rates: noRates)
        #expect(gate.speaker == .satisfied)
    }

    // MARK: - Presentation

    @Test("An ungated chat a member is in gets the ordinary composer")
    func presentation_openAndMember_isOpen() {
        #expect(conversationGatePresentation(.open, isMember: true) == .open)
    }

    @Test("Satisfying the rules without joining offers the join, not the composer")
    func presentation_openAndNotMember_isJoin() {
        let gate = ConversationGate(listener: .satisfied, speaker: .satisfied, headline: .staff)
        #expect(conversationGatePresentation(gate, isMember: false) == .join(.staff))
    }

    @Test("A chat with no rules names nothing above its join button")
    func presentation_noRules_joinNamesNothing() {
        #expect(conversationGatePresentation(.open, isMember: false) == .join(nil))
    }

    @Test("A failing listener gate blocks the chat whether or not the user is a member")
    func presentation_listenerFails_isBlockedEitherWay() {
        let gate = ConversationGate(
            listener: .unsatisfied(unmet: [.staff], primary: .staff),
            speaker: .unsatisfied(unmet: [.staff], primary: .staff),
            headline: .staff
        )
        #expect(conversationGatePresentation(gate, isMember: false) == .blocked(.staff))
        #expect(conversationGatePresentation(gate, isMember: true) == .blocked(.staff))
    }

    @Test("A member who can read but not send gets a read-only chat, not a blurred one")
    func presentation_speakerFails_isReadOnly() {
        let requirement = ConversationGateRequirement.minimumBalance(amount: .usd(100), mint: nil)
        let gate = ConversationGate(
            listener: .satisfied,
            speaker: .unsatisfied(unmet: [requirement], primary: requirement),
            headline: nil
        )
        let presentation = conversationGatePresentation(gate, isMember: true)
        #expect(presentation == .readOnly(requirement))
        #expect(presentation.obscuresTranscript == false)
        #expect(presentation.replacesComposer)
    }

    @Test("Eligibility is what unblurs the transcript; a join is only needed to write")
    func presentation_obscuresTranscript_unlessEligible() {
        #expect(ConversationGatePresentation.open.obscuresTranscript == false)
        #expect(ConversationGatePresentation.readOnly(.staff).obscuresTranscript == false)
        #expect(ConversationGatePresentation.join(.staff).obscuresTranscript == false)
        #expect(ConversationGatePresentation.join(nil).obscuresTranscript)
        #expect(ConversationGatePresentation.blocked(.staff).obscuresTranscript)
        #expect(ConversationGatePresentation.undetermined.obscuresTranscript)
    }

    @Test("Every state but open takes the composer's place")
    func presentation_replacesComposer_unlessOpen() {
        #expect(ConversationGatePresentation.open.replacesComposer == false)
        #expect(ConversationGatePresentation.readOnly(.staff).replacesComposer)
        #expect(ConversationGatePresentation.join(.staff).replacesComposer)
        #expect(ConversationGatePresentation.join(nil).replacesComposer)
        #expect(ConversationGatePresentation.blocked(.staff).replacesComposer)
        #expect(ConversationGatePresentation.undetermined.replacesComposer)
    }

    @Test("A non-member who satisfies the rules reads the transcript but still has to join to write")
    func presentation_eligibleNonMember_readsButCannotWrite() {
        let gate = ConversationGate(listener: .satisfied, speaker: .satisfied, headline: .staff)
        let presentation = conversationGatePresentation(gate, isMember: false)
        #expect(presentation == .join(.staff))
        #expect(presentation.obscuresTranscript == false)
        #expect(presentation.withholdsTranscript == false)
        #expect(presentation.replacesComposer)
    }

    @Test("A non-member of a group with no listener rule is refused the read until they join")
    func presentation_noListenerRule_nonMemberStaysBlurred() {
        // The contract gives a non-member of such a group no read at all, so there is nothing to show.
        let presentation = conversationGatePresentation(.open, isMember: false)
        #expect(presentation == .join(nil))
        #expect(presentation.obscuresTranscript)
        #expect(presentation.withholdsTranscript)
        #expect(presentation.replacesComposer)
    }

    @Test("A non-member short of the rules stays blurred")
    func presentation_unsatisfiedNonMember_isObscured() {
        let gate = ConversationGate(
            listener: .unsatisfied(unmet: [.staff], primary: .staff),
            speaker: .unsatisfied(unmet: [.staff], primary: .staff),
            headline: .staff
        )
        let presentation = conversationGatePresentation(gate, isMember: false)
        #expect(presentation == .blocked(.staff))
        #expect(presentation.obscuresTranscript)
        #expect(presentation.replacesComposer)
    }

    @Test("A balance that drops below the bar while the chat is open brings the blur back")
    func presentation_satisfiedThenUnsatisfied_reobscures() throws {
        let rules = ConversationRules(listener: [.minimumBalance(minimumBalance(100, mints: [.usdf]))])
        let requirement = ConversationGateRequirement.minimumBalance(amount: .usd(100), mint: .usdf)

        let before = conversationGatePresentation(
            conversationGate(session: StubHoldings(balances: [.usdf: try holding(usd: 150)]), rules: rules, rates: noRates),
            isMember: false
        )
        #expect(before == .join(requirement))
        #expect(before.obscuresTranscript == false)

        let after = conversationGatePresentation(
            conversationGate(session: StubHoldings(balances: [.usdf: try holding(usd: 25)]), rules: rules, rates: noRates),
            isMember: false
        )
        #expect(after == .blocked(requirement))
        #expect(after.obscuresTranscript)
    }

    @Test("A verdict that guessed at a missing rate keeps a non-member's transcript covered")
    func presentation_provisionalVerdict_isUndetermined() {
        // No cached CAD rate, so the requirement can't be restated in USD and the gate counts it as
        // met. Showing the transcript on that guess would blur it again once the rate lands.
        let rules = ConversationRules(listener: [
            .minimumBalance(MinimumBalanceRequirement(amount: FiatAmount(value: 100, currency: .cad), mints: [])),
        ])
        let gate = conversationGate(session: StubHoldings(), rules: rules, rates: noRates)
        #expect(gate.listener == .satisfied)
        #expect(gate.isProvisional)

        let nonMember = conversationGatePresentation(gate, isMember: false)
        #expect(nonMember == .undetermined)
        #expect(nonMember.obscuresTranscript)
        // A member already reads the chat, so the guess only decides their composer.
        #expect(conversationGatePresentation(gate, isMember: true) == .open)
    }

    // MARK: - Rules that haven't arrived

    @Test("A chat whose rules haven't arrived is covered, not opened")
    func presentation_undetermined_coversEverything() {
        let gate = ConversationGatePresentation.undetermined
        #expect(gate.obscuresTranscript)
        #expect(gate.replacesComposer)
    }

    @Test("The placeholder shapes stand in for a transcript that exists and is withheld")
    func presentation_withholdsTranscript_whenMessagesAreKeptBack() {
        #expect(ConversationGatePresentation.blocked(.staff).withholdsTranscript)
        #expect(ConversationGatePresentation.join(nil).withholdsTranscript)
        #expect(ConversationGatePresentation.join(.staff).withholdsTranscript == false)
        #expect(ConversationGatePresentation.undetermined.withholdsTranscript == false)
        #expect(ConversationGatePresentation.open.withholdsTranscript == false)
        #expect(ConversationGatePresentation.readOnly(.staff).withholdsTranscript == false)
    }

    @Test("The stated requirement is the chat's own rule, not something the user is short of")
    func headline_statesTheRuleEvenWhenSatisfied() throws {
        let rules = ConversationRules(listener: [.minimumBalance(minimumBalance(100, mints: [.usdf]))])
        let session = StubHoldings(balances: [.usdf: try holding(usd: 250)])
        let gate = conversationGate(session: session, rules: rules, rates: noRates)
        #expect(gate.isOpen)
        #expect(gate.headline == .minimumBalance(amount: .usd(100), mint: .usdf))
    }
}
