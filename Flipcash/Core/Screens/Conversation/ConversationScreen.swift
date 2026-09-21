//
//  ConversationScreen.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import UIKit
import Combine
import FlipcashCore
import FlipcashUI

// Traces when the on-screen conversation is set or cleared — the signal both the receive haptic and
// foreground-banner suppression gate on — so a missed buzz or an unsuppressed banner is traceable.
private let logger = Logger(label: "flipcash.conversation")

/// How a conversation is reached: an existing DM chat (only tip DMs are
/// surfaced now — contact/phone DMs were retired with the Send tab), or a tip
/// DM named by its counterpart before the chat exists server-side.
nonisolated enum ConversationContext: Hashable {
    case existing(ConversationID)
    /// A tip DM opened from the username lookup. The chat is created by the
    /// first tip, so until then there is no record to reach it by — only the
    /// counterpart, whose id derives the chat's own id locally.
    case tipDM(counterpart: UserID)

    /// Resolves the counterpart's synced contact from the directory — the one
    /// rule the nav title, transcript profile card, and profile page share.
    func resolvedContact(in directory: [ResolvedContact]) -> ResolvedContact? {
        switch self {
        case .existing(let conversationID):
            directory.first { $0.dmChatID == conversationID.data }
        case .tipDM:
            // A tip DM's counterpart is known by profile, never by address book.
            nil
        }
    }
}

/// A DM conversation: an iMessage-style transcript over a unified bottom bar
/// (Send Cash beside the composer). Reads live messages from
/// `ConversationController`, which owns the single event stream. For a
/// contact without a chat the transcript stays empty and only Send Cash
/// shows; once the first payment creates the chat, the chat ID resolves live
/// from the synced directory and the composer appears.
struct ConversationScreen: View {

    let context: ConversationContext

    /// Focus the message field on open so the keyboard comes up. Set only by the
    /// post-tip navigation; every other entry point opens keyboard-closed.
    var openKeyboard: Bool = false

    @Environment(ConversationController.self) private var conversationController
    @Environment(ContactSyncController.self) private var contactSyncController
    @Environment(AppRouter.self) private var router
    @Environment(Session.self) private var session
    @Environment(RatesController.self) private var ratesController
    @Environment(PushController.self) private var pushController
    @Environment(Container.self) private var container
    @Environment(SessionContainer.self) private var sessionContainer
    @Environment(\.scenePhase) private var scenePhase

    @State private var didInitialRead = false
    /// The chat whose stored draft has been put back, which is also what permits saving: an empty
    /// composer must not delete a stored draft in the frame before the restore runs.
    @State private var restoredDraftID: ConversationID?
    @State private var barModel = ConversationBarModel()
    @State private var composer = ComposerModel()
    @State private var navBarWidth: CGFloat = 0
    @State private var presentedCard: ContactCard?
    @State private var startChattingRequest: StartChattingRequest?
    @State private var coordinator: ConversationLoadCoordinator?
    /// Tickers for the mints the gate's copy names, resolved from mint metadata. Empty until they
    /// land, and for every ungated chat.
    @State private var mintNames: [PublicKey: String] = [:]
    /// Whether a `JoinChat` is in flight, so the gate panel's button stops taking taps. The join has
    /// no other UI state — it either seats membership, which re-resolves the gate, or it alerts.
    @State private var isJoiningChat = false
    /// Memoizes the head-carded transcript — see ``TranscriptHead``.
    @State private var transcriptHead = TranscriptHead()
    /// Whether the invite sheet is up. A link is the only way into a group, so the empty group's
    /// card hands one out (node 10127:118280).
    @State private var isInviting = false

    /// Horizontal space the back button (leading) reserves on each side of the
    /// centered title item, so the avatar + name can left-align inside a
    /// centered, full-width principal stack.
    private static let titleSideInset: CGFloat = 72

    /// The synced contact for the counterpart, resolved live from the directory
    /// so a `dmChatID` stored after the first payment flows in. Falls back to
    /// the pushed snapshot when the directory hasn't resolved yet.
    private var contact: ResolvedContact? {
        context.resolvedContact(in: contactSyncController.resolvedContacts.onFlipcash)
    }

    private var conversationID: ConversationID? {
        switch context {
        case .existing(let conversationID):
            return conversationID
        case .tipDM(let counterpart):
            // The same derivation the server uses, so the id is known before
            // the chat is — and matches the one the first tip creates.
            return .tipDm(between: conversationController.selfUserID, and: counterpart)
        }
    }

    /// The counterpart this screen was opened for, when it was opened by
    /// person rather than by chat.
    private var counterpartUserID: UserID? {
        switch context {
        case .existing: nil
        case .tipDM(let counterpart): counterpart
        }
    }

    /// The tip DM counterpart, when this conversation is a tip DM. Falls back
    /// to the cached profile before the first tip creates the chat.
    private var tipCounterpart: ConversationMember? {
        if let conversationID,
           let conversation = conversationController.conversation(withID: conversationID),
           conversation.type == .tipDm {
            return conversation.counterpart(excluding: conversationController.selfUserID)
        }
        return Self.cachedCounterpart(counterpartUserID, session: session)
    }

    /// Who Send Cash pays: the tip counterpart in a tip DM, the synced
    /// address-book contact when there is one, otherwise a target built from
    /// the counterpart's shared phone number so a chat with a non-contact can
    /// still receive cash. `nil` when none of those resolve.
    private var sendTarget: SendTarget? {
        if let contact, tipCounterpart == nil {
            return .contact(contact)
        }
        guard let conversationID else { return nil }
        if let target = SendTarget(
            conversation: conversationController.conversation(withID: conversationID),
            dmChatID: conversationID.data,
            selfUserID: conversationController.selfUserID
        ) {
            return target
        }
        // No conversation record to read the counterpart from yet, so the
        // cached profile is what the tip is addressed to.
        guard let member = tipCounterpart, let userID = member.userID else { return nil }
        return .tip(TipRecipient(
            userID: userID,
            displayName: member.displayName,
            username: member.username,
            origin: .chat
        ))
    }

    /// What the first tip has to clear to open this chat — the fee the
    /// counterpart charges for the conversation, falling back to the regional
    /// tip minimum when they charge nothing. Nil once the chat exists, since a
    /// send into an open thread carries no floor.
    ///
    /// Derived from the same inputs as `SendAmountViewModel.tipFloor(in:)` so
    /// the amount the CTA names is the one the amount screen enforces.
    private var startChattingFee: FiatAmount? {
        guard !chatExists, let userID = tipCounterpart?.userID else { return nil }
        let currency = ratesController.balanceCurrency
        return TipFloor.toOpenDM(
            recipientFee: session.cachedUserProfile(for: userID)?.minDmChatInitFee,
            presets: session.userFlags?.tipPresets(for: currency),
            in: currency,
            rates: ratesController.cachedRates
        )?.displayed
    }

    /// Whether a chat exists to hold a transcript. An `existing` conversation
    /// was reached by its chat id, so it does by construction; a tip DM opened
    /// by counterpart does not until the first tip creates it server-side.
    private var chatExists: Bool {
        guard let conversationID else { return false }
        switch context {
        case .existing:
            return true
        case .tipDM:
            return conversationController.conversation(withID: conversationID) != nil
        }
    }

    /// For a tip DM, all counterpart taps open the profile screen — even when
    /// the counterpart is also an address-book contact. A group has no counterpart, so the same
    /// taps open the chat's own profile instead.
    private var profileTapAction: (() -> Void)? {
        if let group = groupConversation {
            return { router.push(.chatProfile(group.id)) }
        }
        guard let userID = tipCounterpart?.userID else { return nil }
        return { router.push(.userProfile(userID)) }
    }

    /// Tapping a face in the gutter opens that person's profile — the same screen the counterpart's
    /// own card opens in a DM.
    private func openAuthorProfile(_ userID: UserID) {
        router.push(.userProfile(userID))
    }

    /// Tapping the title opens the counterpart's contact card: their address-book
    /// card when they're a contact, otherwise the native "Add to Contacts" sheet
    /// seeded with their number. For a tip DM, opens the profile screen instead.
    /// Inert only when neither a contact nor a phone number is known.
    private var titleTapAction: (() -> Void)? {
        if let profileTapAction { return profileTapAction }
        guard groupConversation == nil, contact != nil || addableContactPhone != nil else { return nil }
        return { openContactCard() }
    }

    /// The counterpart's phone number when they're NOT yet an address-book
    /// contact — the seed for the native "Add to Contacts" sheet. Tip DMs
    /// never expose one; their counterpart is known by profile only.
    private var addableContactPhone: String? {
        guard contact == nil, case .contact(let target)? = sendTarget else { return nil }
        return target.phoneE164
    }

    private var title: String {
        // Without a chat there is no conversation record to name, so the
        // counterpart's cached profile is the only source for the title.
        if !chatExists, let name = tipCounterpart?.displayName {
            return name
        }
        if let conversationID {
            return conversationController.displayName(forConversationID: conversationID)
        }
        return contact?.displayName ?? ConversationController.fallbackCounterpartName
    }

    /// The chat's participation rules weighed against the signed-in user: what the bottom of the
    /// screen draws, and whether the transcript is readable at all. `.open` for every DM and for a
    /// group with no rules.
    ///
    /// Recomputed on each observation tick rather than cached, so a balance that crosses the
    /// requirement — or a rate that finally loads — opens the chat without a reopen.
    private var gate: ConversationGatePresentation {
        guard let conversation = groupConversation else {
            return awaitingMetadata ? .undetermined : .open
        }
        return conversationGatePresentation(gateVerdicts, isMember: conversationController.isMember(of: conversation))
    }

    /// Whether this chat's rules are simply unknown, rather than absent.
    ///
    /// A chat opened by its id — every invite link and every group push — is not in the store until
    /// `GetChat` lands, and ``groupConversation`` is nil for the whole of that round trip. Reading
    /// that nil as "not a group, so nothing to gate" is what would draw a readable transcript and a
    /// live composer over a chat the viewer may not be allowed to read at all. A tip DM is excluded
    /// because its chat genuinely does not exist yet: nothing is being withheld, and the first tip
    /// is what creates it.
    private var awaitingMetadata: Bool {
        guard let conversationID else { return false }
        switch context {
        case .tipDM:
            return false
        case .existing:
            return conversationController.conversation(withID: conversationID) == nil
        }
    }

    /// The rule verdicts behind ``gate``, kept separately because the head card states the chat's
    /// advertised listener rule (``ConversationGate/headline``) whether or not the viewer is short
    /// of it, and the presentation only ever carries something unmet.
    private var gateVerdicts: ConversationGate {
        guard let conversation = groupConversation else { return .open }
        return conversationGate(
            session: session,
            rules: conversation.rules,
            rates: ratesController.cachedRates
        )
    }

    /// This chat when it is a group, else nil — the single test every group surface on this screen
    /// branches on, so none of them can disagree about what a group is.
    /// The viewer's mute on this chat, or nil while it is audible or before the chat exists locally.
    private var viewerMute: ConversationMuteState? {
        guard let conversationID else { return nil }
        return conversationController.conversation(withID: conversationID)?.viewerState?.mute
    }

    private var groupConversation: Conversation? {
        guard let conversationID,
              let conversation = conversationController.conversation(withID: conversationID),
              conversation.type == .group
        else { return nil }
        return conversation
    }

    /// The group's roster, or empty for every DM. The transcript names its authors from this, and
    /// their pictures are fetched for it.
    private var groupMembers: [ConversationMember] {
        groupConversation?.members ?? []
    }

    /// The people the transcript attributes its rows to — the window's senders, named by the chat's
    /// own roster where it carries them and by the local cache where it does not. Their pictures are
    /// fetched for this, and their avatar bytes read back for it.
    private var attributedMembers: [ConversationMember] {
        coordinator?.attributedMembers ?? []
    }

    /// The window's senders no roster and no cached profile could name. Fetched by user id, which
    /// is public, so a group larger than the subset its metadata embeds still names every row.
    private var unattributedSenders: [UserID] {
        coordinator?.unattributedSenders ?? []
    }

    /// "12 people" under the title, or nil for a DM, which has no count worth stating.
    ///
    /// From ``ConversationRosterSummary/memberCount``, not `members.count`: the roster a large group
    /// embeds is only a subset, so counting it would under-report the chat.
    private var titleSubtitle: String? {
        guard let count = groupConversation?.rosterSummary.memberCount else { return nil }
        return count == 1 ? "1 person" : "\(count) people"
    }

    /// The group's own picture, fetched under the chat's access context rather than any member's.
    private var groupAvatarSubject: ProfileAvatarStore.AvatarSubject? {
        groupConversation.map { .chat($0.id) }
    }

    /// Avatar bytes for the group's members, keyed by user id.
    ///
    /// Resolved here, in the view, rather than in the mapper: `ConversationLoadCoordinator.Inputs`
    /// is byte-compared on every observation tick and the mapped rows are persisted to the shared
    /// app-group container in the clear, so thumbnails must not travel that way. Reading the store
    /// from `body` is also what makes a landing picture redraw the gutter — the dependency is the
    /// point.
    private var authorAvatars: [UserID: Data] {
        var avatars: [UserID: Data] = [:]
        for member in attributedMembers {
            guard let userID = member.userID,
                  let data = sessionContainer.profileAvatars.data(for: userID) else { continue }
            avatars[userID] = data
        }
        return avatars
    }

    /// The transcript's rows, with the group's own card in front of them.
    ///
    /// The card is assembled here rather than in the mapper for the reason ``authorAvatars`` is:
    /// its picture bytes would otherwise ride in `ConversationLoadCoordinator.Inputs`, which is
    /// byte-compared on every observation tick, and into the shared app-group container the mapped
    /// rows are cached to in the clear. Reading the avatar store from `body` is also what makes a
    /// landing picture redraw the card.
    private var transcriptItems: [ChatItem] {
        transcriptHead.prepending(groupCard, to: coordinator?.items ?? [])
    }

    /// The group's card at the head of its transcript, or nil for a DM and once the history is too
    /// long to head — the same rule the counterpart's profile card follows.
    private var groupCard: ChatGroupCard? {
        guard let group = groupConversation, coordinator?.headsHistory == true else { return nil }
        return ChatGroupCard(
            title: conversationController.displayName(for: group),
            avatarID: group.id.description,
            imageData: groupAvatarSubject.flatMap { sessionContainer.profileAvatars.data(for: $0) },
            blurhash: group.picture?.thumbnailBlurhash,
            requirement: groupCardRequirement,
            showsInvite: showsGroupInvite
        )
    }

    /// Whether the head card offers the invite link: a group the viewer belongs to that nobody else
    /// has joined. Once someone else is in, the invite lives on the chat's profile instead, so it
    /// stops competing with the transcript (node 10127:118280).
    ///
    /// Counted from ``ConversationRosterSummary/memberCount`` for the reason ``titleSubtitle`` is —
    /// an embedded roster is a subset.
    private var showsGroupInvite: Bool {
        guard let group = groupConversation else { return false }
        return conversationController.isMember(of: group) && group.rosterSummary.memberCount <= 1
    }

    /// The chat's entry rule as the card states it (node 10125:19164), or nil when the chat states
    /// none. It states the rule whether or not the viewer satisfies it, so it reads the chat's
    /// advertised listener rule rather than anything the gate found unmet. The line is broken after
    /// the label rather than wherever the card's width falls, as the design breaks it.
    private var groupCardRequirement: String? {
        switch gateVerdicts.headline {
        case .minimumBalance(let amount, let mint):
            // A dollar-token rule is already fully stated by its dollar amount; naming the token
            // as well says the same thing twice. Any other token genuinely needs naming, because
            // the same $100 is a different quantity of each.
            let name = mint == .usdf ? nil : headlineMint.flatMap { mintNames[$0] }
            let holding = name.map { "\(amount.formattedDroppingZeroFraction()) of \($0)" }
                ?? amount.formattedDroppingZeroFraction()
            return "Balance Requirement:\n\(holding)"
        case .staff:
            return "This chat is for Flipcash staff"
        case nil:
            return nil
        }
    }

    /// The mint the gate's requirement names, when it names one. A requirement with no mint applies
    /// across every holding, so there is no single token to buy.
    private var gateMint: PublicKey? {
        switch gate {
        case .open, .undetermined:          return nil
        case .join(let requirement):        return requirement.flatMap(Self.mint(of:))
        case .blocked(let requirement):     return Self.mint(of: requirement)
        case .readOnly(let requirement):    return Self.mint(of: requirement)
        }
    }

    /// The mint the head card's line names. Not always ``gateMint``: a member reads an `.open`
    /// chat, which names nothing to satisfy, and the card still states the rule the chat runs on.
    private var headlineMint: PublicKey? {
        gateVerdicts.headline.flatMap(Self.mint(of:))
    }

    /// Every mint the gate's copy has to name, deduplicated — at most one per requirement, and the
    /// same one in a chat that gates on a single token.
    private var gateMints: [PublicKey] {
        var mints: [PublicKey] = []
        for mint in [gateMint, headlineMint].compactMap({ $0 }) where !mints.contains(mint) {
            mints.append(mint)
        }
        return mints
    }

    /// Ticker for the requirement the panel names, once its metadata lands.
    private var gateMintName: String? { gateMint.flatMap { mintNames[$0] } }

    private static func mint(of requirement: ConversationGateRequirement) -> PublicKey? {
        switch requirement {
        case .minimumBalance(_, let mint):  mint
        case .staff:                        nil
        }
    }

    /// The newest server-confirmed message — what the receive buzz and mark-read track. Optimistic
    /// pending sends render after the confirmed run, so they must not drive these signals (an unresolved
    /// send would otherwise sit at the transcript's tail and mask incoming messages).
    private var latestConfirmedMessage: ConversationMessage? {
        guard let conversationID else { return nil }
        return conversationController.lastConfirmedMessage(for: conversationID)
    }

    /// The transcript and its bar, configured from this screen's state.
    ///
    /// Split out of `body` so the argument list and the modifier chain below it are two expressions
    /// rather than one. Together they are more than the type checker will finish — it gives up on
    /// CI, where it is working against a tighter budget than on a dev machine.
    ///
    /// `gate` is passed in rather than read here so it stays resolved once per `body`, and so the
    /// closures below keep capturing the same value they always did.
    private func transcript(
        gate: ConversationGatePresentation,
        pagesHistory: Bool
    ) -> ChatScreenRepresentable {
        ChatScreenRepresentable(
            items: transcriptItems,
            // Paging history for a chat the server hasn't created yet fetches
            // against an id it doesn't know and error-reports.
            onReachTop: { if pagesHistory { coordinator?.reachedTop() } },
            onRetry: retry,
            onCashCardTap: openCurrencyInfo,
            onOpenURL: openLink,
            onLinkCardTap: openLinkCard,
            linkCardSource: sessionContainer.linkCardFeed,
            onContactAction: openContactCard,
            onProfileTap: profileTapAction,
            onGroupInvite: { isInviting = true },
            onAuthorTap: openAuthorProfile,
            onMessageAction: handleMessageAction,
            onQuoteTap: jumpToQuote,
            showsSendCash: sendTarget != nil,
            chatExists: chatExists,
            conversationID: conversationID,
            symbol: ratesController.balanceCurrency.compactSymbol,
            onSendCash: sendCash,
            conversationController: conversationController,
            barModel: barModel,
            composer: composer,
            editingStableID: composer.editingStableID,
            focusOnAppear: openKeyboard,
            isTipDm: tipCounterpart != nil,
            startChattingFee: startChattingFee,
            gate: gate,
            // The contract has no non-member read, so a gated chat the viewer has no history of has
            // nothing under its blur. The shapes stand in for what they are not allowed to see —
            // which is why this reads `withholdsTranscript` and not `obscuresTranscript`: a chat
            // whose rules haven't landed yet is blurred without yet refusing anything.
            showsGatePlaceholder: gate.withholdsTranscript && (coordinator?.items.isEmpty ?? true),
            gateMintName: gateMintName,
            onGateAddFunds: addFunds,
            onGateJoin: joinChat,
            isJoiningChat: isJoiningChat,
            authorAvatars: authorAvatars
        )
    }

    var body: some View {
        // The UIKit transcript hosts the bar internally and owns all keyboard handling, so there's
        // no SwiftUI `.safeAreaInset` bar here.
        //
        // The gate is resolved once here and passed down. It has to be: the transcript calls
        // `onReachTop` on every scroll frame it spends near the top, and reading `gate` re-evaluates
        // the chat's rules against the balance and the rate table each time.
        let gate = self.gate
        let pagesHistory = chatExists && !gate.obscuresTranscript
        // Stages, rather than one chain. A getter is a single type-check budget however many
        // statements it holds, and this chain is more than the compiler will finish inside one —
        // it gives up on CI, where the budget is tighter than on a dev machine. A function each
        // gives them a budget each.
        return lifecycle(
            presentation(
                loads(
                    chrome(transcript(gate: gate, pagesHistory: pagesHistory))
                )
            ),
            gate: gate
        )
    }

    /// Framing, background, and the navigation bar's own contents.
    private func chrome(_ content: some View) -> some View {
        content
        .ignoresSafeArea(.keyboard)
        // Extend the transcript under the navigation bar so content scrolls beneath it — that's
        // what lets the iOS 26 toolbar scroll-edge effect materialize. The collection view keeps a
        // top content inset (it adjusts for the safe area) so messages stay readable below the bar.
        .ignoresSafeArea(.container, edges: .top)
        // The bar's surface stops where the hosted view does, at the bottom safe area. This carries
        // it the rest of the way down, so the bar reads as running off the bottom of the display
        // rather than as a card with an edge above the home indicator.
        .background {
            BarSurfaceFloor()
        }
        .background(Color.backgroundMain)
        .navigationTitle("")
        .toolbarTitleDisplayMode(.inline)
        // The edit blur slides under the navigation bar, so the bar stays sharp through an edit.
        // What it holds changes: the counterpart's name and avatar go, since the edit is about one
        // message rather than the person, and the back button backs out of the edit rather than the
        // chat — leaving the chevron alone in the bar.
        .navigationBarBackButtonHidden(composer.isEditing)
        .toolbar {
            if composer.isEditing {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        composer.endEditing()
                    } label: {
                        Image(systemName: "chevron.backward")
                            .foregroundStyle(Color.textMain)
                    }
                    .accessibilityLabel("Stop editing")
                }
            } else {
                ToolbarItem(placement: .principal) {
                    ConversationTitleItem(
                        title: title,
                        subtitle: titleSubtitle,
                        contact: contact,
                        conversationID: conversationID,
                        // A group's face is the chat's own picture. Falling through to the
                        // counterpart would draw an arbitrary member, since `counterpart(excluding:)`
                        // picks one from the roster subset.
                        imageData: groupAvatarSubject.map { sessionContainer.profileAvatars.data(for: $0) }
                            ?? contact?.imageData
                            ?? sessionContainer.profileAvatars.data(for: tipCounterpart?.userID),
                        blurhash: groupConversation.map { $0.picture?.thumbnailBlurhash }
                            ?? tipCounterpart?.profilePicture?.thumbnailBlurhash,
                        width: max(navBarWidth - Self.titleSideInset * 2, 0),
                        mute: viewerMute,
                        onTap: titleTapAction,
                        opensProfile: profileTapAction != nil
                    )
                }
            }
        }
    }

    /// The fetches the transcript needs: gate token names, sender names, and avatars.
    private func loads(_ content: some View) -> some View {
        content
        // Name the gate's requirement in the token it asks for. The mint may be one the user holds
        // nothing of, so the local store can miss and the fetch is what fills it.
        .task(id: gateMints) {
            var names: [PublicKey: String] = [:]
            for mint in gateMints {
                if let stored = session.storedMintMetadata(for: mint) {
                    names[mint] = stored.name
                } else if let fetched = try? await session.fetchMintMetadata(mint: mint).name {
                    names[mint] = fetched
                }
            }
            mintNames = names
        }
        // Read what the device already knows about this chat's senders, for the ones its own roster
        // leaves out. One read per open: the local cache is not moving under an open transcript.
        .task(id: groupConversation?.id) {
            guard groupConversation != nil else { return }
            await sessionContainer.knownAuthors.reload()
        }
        // Name the senders the chat's roster and the local cache both leave out. Keyed on that set,
        // so it runs when a page of older messages reveals a sender nothing here can name — and not
        // again once the fetch has landed them.
        .task(id: unattributedSenders) {
            guard !unattributedSenders.isEmpty else { return }
            await sessionContainer.knownAuthors.resolve(unattributedSenders)
        }
        // Fetch the pictures for the transcript's author gutter. Keyed on who the rows are actually
        // attributed to, so a sender the roster names later — or that the local cache names — is
        // fetched when they appear rather than only at open.
        .task(id: attributedMembers.compactMap(\.userID)) {
            sessionContainer.profileAvatars.preload(
                attributedMembers.map { (userID: $0.userID, picture: $0.profilePicture) }
            )
        }
        // Fetch the group's own picture for the title bar, under the chat's access context.
        .task(id: groupConversation?.picture?.thumbnailBlobID) {
            guard let groupAvatarSubject else { return }
            await sessionContainer.profileAvatars.load(
                groupAvatarSubject,
                picture: groupConversation?.picture
            )
        }
        // Fetch the tip counterpart's avatar for the title and profile card.
        .task(id: tipCounterpart?.userID) {
            await sessionContainer.profileAvatars.load(
                userID: tipCounterpart?.userID,
                picture: tipCounterpart?.profilePicture
            )
        }
    }

    /// What this screen puts on top of itself, and the measurement the title bar needs.
    private func presentation(_ content: some View) -> some View {
        content
        .sheet(item: $presentedCard) { card in
            ContactCardView(card: card)
                .ignoresSafeArea()
        }
        .sheet(item: $startChattingRequest) { request in
            StartChattingSheet(target: request.target, fee: request.fee)
        }
        .sheet(isPresented: $isInviting) {
            if let conversationID {
                GroupInviteSheet(conversationID: conversationID, isPresented: $isInviting)
            }
        }
        .background {
            // Measure the bar width so the centered title item can be sized to
            // (almost) fill it — the system toolbar won't honor maxWidth on a
            // principal item, so an explicit width is the only way to let the
            // avatar + name left-align inside a centered, full-width stack.
            GeometryReader { proxy in
                Color.clear
                    .onAppear { navBarWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, width in navBarWidth = width }
            }
        }
        // While composing, a downward swipe should lower the keyboard — not
        // tear down the whole Send sheet.
        .interactiveDismissDisabled(barModel.isComposing)
        // The transcript explains an applied edit or delete on its own; a conflict or a failure is
        // only visible as "nothing happened", so it is reported here.
        .onChange(of: conversationController.mutationAlert) { _, alert in
            presentMutationAlert(alert)
        }
        // Keyed on existence, not just the ID: a matched contact's chat ID is
        // pre-assigned, and fetching messages for a chat the server hasn't
        // created yet error-reports. Fires when the chat materializes.
    }

    /// Opening, closing, and everything that has to be written down before either —
    /// read watermarks, the draft, and the donated activity.
    ///
    /// Takes `gate` rather than reading it, so these closures capture the value `body` resolved.
    private func lifecycle(_ content: some View, gate: ConversationGatePresentation) -> some View {
        content
        .task(id: chatExists ? conversationID : nil) {
            guard chatExists, let conversationID else { return }
            // Ensure the conversation metadata is in the store before the title, tip styling, and Send
            // Cash target rely on it. The post-tip open (and any push/link that lands here before the
            // feed or stream has the freshly-created chat) would otherwise render the unresolved
            // counterpart — a "Flipcash User" title and no Send Cash button. No-ops when already loaded.
            _ = await conversationController.hydratedConversation(withID: conversationID)
            // The gate is read after hydration, not before: `GetChat` is what delivers the rules,
            // and it carries no listener gate of its own. Everything below it does — a transcript
            // the user may not read answers `DENIED` to the fetch, the pointer advance, and the
            // catch-up alike — so a blocked chat stops here with its metadata and nothing else.
            guard !gate.obscuresTranscript else { return }
            await loadTranscript(for: conversationID)
        }
        .onChange(of: latestConfirmedMessage?.stableID) {
            // Fires on a live arrival or our own send. Marking read on our own send is intentional: it
            // advances the self-read watermark past the message we just sent, so the conversation
            // doesn't show as unread in the feed. didInitialRead skips the opening load (the .task
            // already marked read), and markRead short-circuits when the watermark already covers it.
            guard didInitialRead, !gate.obscuresTranscript, let conversationID else { return }
            conversationController.scheduleMarkRead(conversationID: conversationID)
        }
        // Buzz on a live message from the other side while this conversation is on screen. `old != nil`
        // and `didInitialRead` skip the opening history load; the sender and visibility checks skip the
        // user's own sends and arrivals in a chat they've navigated away from.
        .sensoryFeedback(.impact(weight: .light), trigger: latestConfirmedMessage?.stableID) { old, _ in
            guard old != nil, didInitialRead,
                  let last = latestConfirmedMessage,
                  !last.isFromSelf(conversationController.selfUserID),
                  conversationController.visibleConversationID == conversationID
            else { return false }
            return true
        }
        .onAppear {
            setVisibleConversation(conversationID, source: "onAppear")
            syncCoordinator(conversationID)
            restoreDraft(conversationID)
        }
        // A matched contact's chat is created mid-screen on the first payment,
        // flipping the ID from nil to the new conversation; track it live.
        .onChange(of: conversationID) { _, id in
            setVisibleConversation(id, source: "onChange")
            syncCoordinator(id)
            restoreDraft(id)
        }
        .onChange(of: composer.draft) { _, _ in saveDraft() }
        // Mode rather than `replyTarget` alone: it also covers the edit transitions, where what is
        // worth saving swaps between the field and the draft the edit displaced.
        .onChange(of: composer.mode) { _, _ in saveDraft() }
        // Neither a pop nor a background kill guarantees a later callback, so both write through
        // rather than waiting out the debounce.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { saveDraft(flushing: true) }
        }
        .onDisappear {
            saveDraft(flushing: true)
            // The composer's focus `onChange` can't fire once unmounted, so stop typing here.
            if let conversationID {
                conversationController.stopSelfTyping(in: conversationID)
            }
            // Guarded so a forward push that already set another ID isn't cleared.
            let matched = conversationController.visibleConversationID == conversationID
            logger.info("Clearing visible conversation on disappear", metadata: [
                "conversationID": conversationID.map { "\($0)" } ?? "nil",
                "matched": "\(matched)",
            ])
            if matched {
                conversationController.visibleConversationID = nil
            }
        }
        // Donate the open chat for Siri prediction, Handoff, and Spotlight.
        // Only an existing chat carries an id worth resuming; a contact without
        // a chat yet has nothing to hand off to.
        .userActivity(AppUserActivity.openChat, isActive: chatExists && conversationID != nil) { activity in
            guard let conversationID else { return }
            activity.title = title
            activity.userInfo = [AppUserActivity.chatIDKey: conversationID.base64URLEncoded]
            activity.requiredUserInfoKeys = [AppUserActivity.chatIDKey]
            activity.persistentIdentifier = conversationID.base64URLEncoded
            activity.isEligibleForSearch = true
            activity.isEligibleForHandoff = true
            activity.isEligibleForPrediction = true
        }
    }

    /// Puts the chat's stored draft back into an untouched composer, once per chat id.
    ///
    /// Silent by design: nothing here touches focus, so a restored draft does not bring the
    /// keyboard up — that is still `openKeyboard`'s alone, set only by the post-tip entry.
    private func restoreDraft(_ id: ConversationID?) {
        guard let id, restoredDraftID != id else { return }
        restoredDraftID = id
        guard let stored = sessionContainer.chatDrafts.draft(for: id) else { return }
        composer.restore(stored)
    }

    /// Records what the composer is holding. Gated on the restore having run for this chat, so the
    /// empty field the screen starts with cannot delete the draft it is about to be given.
    private func saveDraft(flushing: Bool = false) {
        guard let conversationID, restoredDraftID == conversationID else { return }
        sessionContainer.chatDrafts.save(composer.persistableDraft, for: conversationID)
        if flushing { sessionContainer.chatDrafts.flush() }
    }

    /// Marks this conversation as the one on screen — the gate for foreground-banner suppression and
    /// the receive haptic — and traces the change so a first-open visibility gap is diagnosable.
    private func setVisibleConversation(_ id: ConversationID?, source: String) {
        logger.info("Set visible conversation", metadata: [
            "source": "\(source)",
            "conversationID": id.map { "\($0)" } ?? "nil",
        ])
        conversationController.visibleConversationID = id
    }

    /// Opens the native iOS contact card for the counterpart: their
    /// address-book card when they're a contact, otherwise the "Add to
    /// Contacts" sheet seeded with their number.
    private func openContactCard() {
        presentedCard = ContactCard.make(contact: contact, addablePhone: addableContactPhone)
    }

    private func presentMutationAlert(_ alert: ConversationController.MutationAlert?) {
        guard let alert else { return }
        session.dialogItem = DialogItem.alert(title: alert.title, subtitle: alert.subtitle) {
            DialogAction.okay(kind: .destructive) {
                conversationController.mutationAlert = nil
            }
        }
    }

    /// Routes a context-menu choice. Copy never arrives here — the transcript handles it locally.
    private func handleMessageAction(_ stableID: String, _ action: MessageCapability) {
        guard let message = coordinator?.loader.messages.first(where: { $0.stableID == stableID }) else { return }

        switch action {
        case .copy:
            break
        case .reply:
            let preview = Self.replyPreview(for: message) { session.balance(for: $0.mint)?.name ?? "Cash" }
            composer.beginReplying(to: ComposerModel.ReplyTarget(
                messageID: message.id,
                stableID: stableID,
                // A group names the real writer; `counterpartName` is the DM's single other party
                // and would attribute every reply in a group to whoever the chat is titled after.
                authorName: message.isFromSelf(conversationController.selfUserID)
                    ? "You"
                    : (message.senderID.flatMap { coordinator?.attributedName(for: $0) }
                        ?? coordinator?.counterpartName
                        ?? ""),
                authorID: message.senderID,
                snippet: preview.snippet,
                kind: preview.kind
            ))
        case .edit:
            guard case .text(let text) = message.content else { return }
            composer.beginEditing(messageID: message.id, stableID: stableID, currentText: text)
        case .delete:
            confirmDelete(message.id)
        case .report:
            // Unreachable today: `orderedActions` does not offer Report yet, because the reason
            // sheet needs a vocabulary that `SharedCoreKit` does not ship until 0.8.0. The
            // capability, its window and its menu placement are all in place; the row and this
            // arm land together with the sheet.
            break
        }
    }

    /// The composer strip's preview of the message being answered — the same three-way split the
    /// transcript's quote panel uses, so the strip and the sent bubble read alike.
    ///
    /// A tombstone cannot reach here: `MessageCapability.resolve` grants a deleted message nothing,
    /// so its row has no menu. The branch keeps the switch exhaustive.
    private static func replyPreview(
        for message: ConversationMessage,
        token: (ExchangedFiat) -> String
    ) -> (snippet: String, kind: ChatQuote.Kind) {
        switch message.content {
        case .text(let text):
            (ChatQuote.snippet(forText: text), .text)
        case .cash(let fiat):
            (
                fiat.nativeAmount.formatted(),
                .cash(token: token(fiat), flagImageName: ChatItem.flagImageName(for: fiat))
            )
        case .deleted:
            (ChatQuote.deletedSnippet, .unavailable)
        }
    }

    /// Brings the quoted original into the window when the local database has it. Returns without
    /// effect otherwise — history that was never fetched is out of scope, and the panel that
    /// points at it is already non-tappable.
    ///
    /// A pending row's stable id is a UUID string, so the conversion fails and the jump is a no-op —
    /// correct, since an unconfirmed message is by definition at the bottom of the window already.
    private func jumpToQuote(_ stableID: String) {
        guard let value = UInt64(stableID) else { return }
        _ = coordinator?.loader.reveal(MessageID(value: value))
    }

    private func confirmDelete(_ messageID: MessageID) {
        guard let conversationID else { return }

        // WhatsApp's sheet offers "Delete for everyone" beside "Delete for me"; we have no
        // delete-for-me, so the one action we do have names its scope and stands alone.
        session.dialogItem = DialogItem.alert(
            title: "Delete Message?",
            subtitle: "This can't be undone"
        ) {
            DialogAction.destructive("Delete For Everyone") {
                Task { await conversationController.delete(messageID: messageID, in: conversationID) }
            }
            DialogAction.cancel()
        }
    }

    private func sendCash() {
        guard let sendTarget else { return }
        let context: AddMoneyContext = switch sendTarget {
        case .tip:     .sendTips
        case .contact: .giveCash
        }
        let rate = ratesController.rateForBalanceCurrency()
        if let dialog = giveCashGate(session: session, rate: rate).blockingDialog(router: router, addMoneySource: .chat, context: context) {
            session.dialogItem = dialog
            return
        }
        // The payment that opens a tip DM can only be the fee, and the bar has
        // already named it — so it's confirmed rather than entered. Everything
        // else, this one included when the fee hasn't resolved yet, opens the
        // amount screen.
        if case .tip = sendTarget, let fee = startChattingFee {
            startChattingRequest = StartChattingRequest(target: sendTarget, fee: fee)
            return
        }
        router.presentSendAmount(sendTarget)
    }

    /// What the start-chatting sheet is opened for, snapshotted at the tap: once
    /// the send lands the chat exists and `startChattingFee` goes nil.
    private struct StartChattingRequest: Identifiable {
        let target: SendTarget
        let fee: FiatAmount

        var id: SendTarget { target }
    }

    /// Re-send a failed message tapped in the transcript. The id is the row's stable id, which for a
    /// failed message is its client message id.
    private func retry(messageID: String) {
        guard let conversationID, let clientMessageID = UUID(uuidString: messageID) else { return }
        Task { await conversationController.retry(clientMessageID: clientMessageID, in: conversationID) }
    }

    /// Push the tapped cash card's token currency info onto the current chat stack (so back returns
    /// here). The id is the row's stable id; resolve it to the cash message's mint.
    private func openCurrencyInfo(messageID: String) {
        // Resolve against the displayed window (the DB-backed transcript), not the store — the window
        // can hold older/paged messages the trimmed store no longer does.
        guard let message = (coordinator?.loader.messages ?? []).first(where: { $0.stableID == messageID }) else { return }
        switch message.content {
        case .cash(let fiat):
            router.push(.currencyInfo(fiat.mint))
        case .text, .deleted:
            break
        }
    }

    /// The gate panel's CTA: buys the mint the requirement names, or opens add-cash when there is no
    /// one token to buy — a requirement spanning every holding, and a dollar-token one, which is
    /// satisfied by adding cash rather than by swapping into the thing the cash already is. Both
    /// routes leave the chat on the stack, so satisfying the requirement returns to an ungated screen.
    private func addFunds() {
        guard let gateMint, gateMint != .usdf else {
            router.presentAddMoney(.general, source: .chat)
            return
        }
        router.push(.buyCurrency(gateMint))
    }

    /// Everything the screen does once the gate lets it read. Factored out of the opening `.task`
    /// because a join opens the gate mid-screen, which does not re-run that task.
    private func loadTranscript(for conversationID: ConversationID) async {
        // The newest page IS the fresh state and seats the event-log cursor to head, so opening a
        // chat needs no separate catch-up. Missed-while-open windows are reconciled by the
        // foreground / reconnect / live-gap triggers instead.
        await conversationController.loadMessages(for: conversationID)
        await conversationController.markRead(conversationID: conversationID)
        // Reading the thread clears its own delivered pushes; other chats keep theirs.
        await pushController.clearDeliveredNotifications(for: conversationID)
        didInitialRead = true
    }

    /// The gate panel's Join: joins the chat, which seats membership and re-resolves the gate to
    /// ``ConversationGatePresentation/open``. A refused join leaves the screen exactly as it was, so
    /// the failure has to be said out loud rather than shown by the gate not moving.
    private func joinChat() {
        guard let conversationID, !isJoiningChat else { return }
        isJoiningChat = true
        Task {
            defer { isJoiningChat = false }
            do {
                try await conversationController.join(conversationID: conversationID)
                await loadTranscript(for: conversationID)
            } catch {
                session.dialogItem = DialogItem.alert(
                    title: "Couldn't Join Chat",
                    subtitle: joinFailureSubtitle(error)
                ) {
                    DialogAction.okay(kind: .standard)
                }
            }
        }
    }

    /// `rulesNotSatisfied` is the server disagreeing with the gate this screen just drew, so it gets
    /// the one message the user can act on; everything else is a generic retry.
    private func joinFailureSubtitle(_ error: Error) -> String {
        guard case ErrorJoinChat.rulesNotSatisfied = error else {
            return "Something went wrong. Please try again."
        }
        return "You don't meet this chat's requirements yet."
    }

    private func openLink(_ url: URL) {
        // iOS won't re-enter the app for our own universal link from an in-app tap, so route every
        // tapped link through the deep-link handler; anything it doesn't recognize opens externally.
        if container.deepLinkController.open(url) { return }
        UIApplication.shared.open(url)
    }

    /// Where a tapped link card lands, which is not the same place for both kinds.
    ///
    /// A cash card goes out through the deep-link path its URL would have taken — claiming is that
    /// path's job and the card has no part in it. A token card pushes onto this chat's own stack,
    /// the way `openCurrencyInfo` does for a cash message, rather than through the deep-link
    /// handler: `.token` there resets the balance tab and walks the reader out of the conversation
    /// they were reading.
    private func openLinkCard(_ card: LinkCard) {
        switch card {
        case .cash:
            openLink(card.url)
        case .token(let token):
            router.push(.currencyInfo(token.mint))
        }
    }

    /// Builds (or clears) the transcript loader/coordinator as the conversation id resolves — including
    /// a re-resolution to a *different* id (a contact's pre-assigned chat id replaced by the
    /// server-assigned one), which must re-window the new conversation, not keep rendering the old.
    private func syncCoordinator(_ id: ConversationID?) {
        guard let id else { coordinator = nil; return }
        if coordinator?.conversationID != id {
            coordinator = ConversationLoadCoordinator(
                conversationID: id,
                controller: conversationController,
                session: session,
                knownAuthors: sessionContainer.knownAuthors,
                // `profileAvatars` is captured directly so the coordinator retains
                // one small store, not the whole session container.
                profileCard: { [context, contactSyncController, conversationController, session, counterpartUserID, profileAvatars = sessionContainer.profileAvatars] in
                    // A group cards itself — the address book has nothing to say about a chat, and
                    // the unknown-contact fallback below would flag one as an unknown person.
                    guard conversationController.conversation(withID: id)?.type != .group else {
                        return nil
                    }
                    return Self.profileCard(
                        context: context,
                        conversationID: id,
                        directory: contactSyncController.resolvedContacts.onFlipcash,
                        controller: conversationController,
                        profileAvatars: profileAvatars,
                        // Resolved inside the closure, not captured: the card
                        // must pick up the conversation the first tip creates.
                        fallbackCounterpart: Self.cachedCounterpart(counterpartUserID, session: session)
                    )
                }
            )
        }
    }

    /// The card relationship for a tip DM. A tip DM has no address-book
    /// relationship to fall back on, so a counterpart who hasn't claimed a
    /// handle keeps the name-only card they had before handles existed.
    static func tipDMCounterpart(_ member: ConversationMember?) -> ChatProfileCard.Counterpart {
        guard let username = member?.username else { return .none }
        return .handle(username)
    }

    /// The counterpart of a tip DM that has no chat yet, built from a fetched
    /// profile. Gives the title, card, and Send Cash target the same member
    /// shape a synced conversation would supply.
    static func counterpart(userID: UserID, profile: Profile) -> ConversationMember {
        ConversationMember(
            userID: userID,
            // A name-less account can still be tipped, and the chat has to be
            // titled either way — the same fallback a conversation gets.
            displayName: profile.displayName ?? ConversationController.fallbackCounterpartName,
            profilePicture: profile.profilePicture,
            username: profile.username
        )
    }

    /// ``counterpart(userID:profile:)`` against the profile cache the username
    /// lookup writes on its way here.
    private static func cachedCounterpart(_ userID: UserID?, session: Session) -> ConversationMember? {
        guard let userID, let profile = session.cachedUserProfile(for: userID) else { return nil }
        return counterpart(userID: userID, profile: profile)
    }

    /// The transcript's profile card for the counterpart, resolved live from the directory the
    /// same way the nav title is: the synced contact when there is one, the profile-only tip
    /// counterpart for a tip DM, otherwise the counterpart's formatted number flagged as an
    /// unknown contact.
    private static func profileCard(
        context: ConversationContext,
        conversationID: ConversationID,
        directory: [ResolvedContact],
        controller: ConversationController,
        profileAvatars: ProfileAvatarStore,
        fallbackCounterpart: ConversationMember? = nil
    ) -> ChatProfileCard {
        if let conversation = controller.conversation(withID: conversationID),
           conversation.type == .tipDm {
            let counterpart = conversation.counterpart(excluding: controller.selfUserID)
            return ChatProfileCard(
                name: controller.displayName(for: conversation),
                avatarID: counterpart?.userID?.uuidString ?? conversationID.description,
                imageData: profileAvatars.data(for: counterpart?.userID),
                blurhash: counterpart?.profilePicture?.thumbnailBlurhash,
                counterpart: Self.tipDMCounterpart(counterpart)
            )
        }
        // No conversation record yet — the same card, from the cached profile.
        if let counterpart = fallbackCounterpart {
            return ChatProfileCard(
                name: counterpart.displayName,
                avatarID: counterpart.userID?.uuidString ?? conversationID.description,
                imageData: profileAvatars.data(for: counterpart.userID),
                blurhash: counterpart.profilePicture?.thumbnailBlurhash,
                counterpart: Self.tipDMCounterpart(counterpart)
            )
        }
        if let contact = context.resolvedContact(in: directory) {
            return ChatProfileCard(
                name: contact.displayName,
                avatarID: contact.contactId,
                imageData: contact.imageData,
                counterpart: .contact(phone: contact.nationalPhone)
            )
        }
        return ChatProfileCard(
            name: controller.displayName(forConversationID: conversationID),
            avatarID: conversationID.description,
            imageData: nil,
            counterpart: .unknown
        )
    }

}

// MARK: - Title -

/// Avatar + name, left-aligned inside the centered principal slot (sized to
/// the measured bar width; the system toolbar won't honor maxWidth on a
/// principal item). When `onTap` is non-nil the whole item becomes a button
/// that opens the counterpart's contact card or profile screen.
private struct ConversationTitleItem: View {

    let title: String
    /// The line under the title — a group's member count. Nil in a DM, where the title sits
    /// vertically centred on its own.
    let subtitle: String?
    let contact: ResolvedContact?
    let conversationID: ConversationID?
    let imageData: Data?
    let blurhash: String?
    let width: CGFloat
    var mute: ConversationMuteState? = nil
    let onTap: (() -> Void)?
    let opensProfile: Bool

    var body: some View {
        let label = ConversationTitleLabel(
            title: title,
            subtitle: subtitle,
            contact: contact,
            conversationID: conversationID,
            imageData: imageData,
            blurhash: blurhash,
            width: width,
            mute: mute
        )
        if let onTap {
            let hint = opensProfile ? "Opens profile" : (contact != nil ? "Opens contact card" : "Adds to Contacts")
            Button(action: onTap) { label }
                .buttonStyle(.plain)
                // The button reads as one element, so the bell's own label is discarded. Read from
                // the mute here rather than kept as a flag, and a moment stale at the instant a
                // timed one lapses — this redraws on store changes, not on the bell's clock.
                .accessibilityLabel(
                    [title, subtitle, mute?.isActive() == true ? "muted" : nil]
                        .compactMap { $0 }
                        .joined(separator: ", ")
                )
                .accessibilityHint(hint)
        } else {
            label
        }
    }
}

private struct ConversationTitleLabel: View {

    let title: String
    let subtitle: String?
    let contact: ResolvedContact?
    let conversationID: ConversationID?
    let imageData: Data?
    let blurhash: String?
    let width: CGFloat
    var mute: ConversationMuteState? = nil

    var body: some View {
        HStack(spacing: 12) {
            ContactAvatarView(
                id: contact?.contactId ?? conversationID?.description ?? title,
                displayName: title,
                imageData: imageData,
                blurhash: blurhash,
                size: 44
            )
            .accessibilityHidden(true)
            // The 44pt avatar already sets the bar's height, so the second line costs nothing and a
            // titled-only DM keeps the layout it has (nodes 10125:19191-19194).
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Text(title)
                        .font(.appBarButton)
                        .foregroundStyle(Color.textMain)
                        .lineLimit(1)
                    MuteBell(mute)
                }
                if let subtitle {
                    Text(subtitle)
                        .font(.default(size: 13, weight: .medium))
                        .foregroundStyle(Color.textMain.opacity(0.5))
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
        }
        .frame(width: width, alignment: .leading)
    }
}

/// Keeps one array for a head card sitting above an unchanged transcript.
///
/// A DM hands the loader's own `[ChatItem]` straight through, so the transcript's `newItems != items`
/// check settles on buffer identity and costs nothing. Prepending a card builds a fresh array on every
/// body pass, which defeats that check and deep-compares every row instead — on each of the many body
/// passes a push, a pop or an opening reply strip causes. Returning the previous array whenever both
/// inputs are unchanged puts the group back on the same O(1) path.
///
/// A reference type held in `@State`: it is read during `body` and must not invalidate the view when
/// it remembers something.
@MainActor private final class TranscriptHead {

    private var lastCard: ChatGroupCard?
    private var lastTail: [ChatItem] = []
    private var composed: [ChatItem] = []

    /// `tail` with `card` in front of it, or `tail` itself when there is no card.
    func prepending(_ card: ChatGroupCard?, to tail: [ChatItem]) -> [ChatItem] {
        guard let card else { return tail }
        if card == lastCard, tail == lastTail { return composed }
        lastCard = card
        lastTail = tail
        composed = [.groupCard(card)] + tail
        return composed
    }
}
