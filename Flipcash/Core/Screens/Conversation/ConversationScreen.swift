//
//  ConversationScreen.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import PhotosUI
import SwiftUI
import UIKit
import Combine
import FlipcashCore
import FlipcashUI

// Traces when the on-screen conversation is set or cleared — the signal both the receive haptic and
// foreground-banner suppression gate on — so a missed buzz or an unsuppressed banner is traceable.
private let logger = Logger(label: "flipcash.conversation")

/// How a conversation is reached: an existing chat, by its id. A tip DM that doesn't exist yet
/// is reached through the counterpart's profile, not here.
nonisolated enum ConversationContext: Hashable {
    case existing(ConversationID)

    /// Resolves the counterpart's synced contact from the directory — the one
    /// rule the nav title, transcript profile card, and profile page share.
    func resolvedContact(in directory: [ResolvedContact]) -> ResolvedContact? {
        switch self {
        case .existing(let conversationID):
            directory.first { $0.dmChatID == conversationID.data }
        }
    }
}

/// A DM conversation: an iMessage-style transcript over a unified bottom bar
/// (Send Cash beside the composer). Reads live messages from
/// `ConversationController`, which owns the single event stream.
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
    /// Set once the saved link previews have loaded or 300 ms have passed, so a chat opened right
    /// after launch draws its cards from them instead of flashing placeholders (P22d).
    @State private var waitedForLinkPreviews = false
    /// The chat whose stored draft has been put back, which is also what permits saving: an empty
    /// composer must not delete a stored draft in the frame before the restore runs.
    @State private var restoredDraftID: ConversationID?
    @State private var barModel = ConversationBarModel()
    @State private var composer = ComposerModel()
    /// The group's mention picker for this visit, or `nil` in a DM.
    @State private var mentions: MentionPickerModel?
    /// Seeded from the scene so the title has its full width on the first frame; the measurement
    /// below only corrects it.
    @State private var navBarWidth: CGFloat = UIApplication.shared.firstWindowScene?.coordinateSpace.bounds.width ?? 0
    @State private var presentedCard: ContactCard?
    @State private var coordinator: ConversationLoadCoordinator?
    /// Tickers for the mints the gate's copy names, resolved from mint metadata. Empty until they
    /// land, and for every ungated chat.
    @State private var mintNames: [PublicKey: String] = [:]
    /// Whether a `JoinChat` is in flight, so the gate panel's button stops taking taps. The join has
    /// no other UI state — it either seats membership, which re-resolves the gate, or it alerts.
    @State private var isJoiningChat = false
    /// Whether the encryption explainer opened from the transcript's marker is showing.
    @State private var isShowingEncryptionInfo = false
    @State private var messageReport: MessageReportRequest?
    /// Whether `Group: Gate Shown` has gone out for this visit. The destination is keyed by
    /// conversation ID, so a new push is a new visit; a return from a pushed screen is not.
    @State private var didReportGate = false
    /// The stable id and pill set the picker sheet is open for, or nil.
    @State private var reactionPickerRequest: ReactionPickerRequest?
    /// The stable id, pill set, and long-pressed emoji the reactors sheet is open for, or nil.
    @State private var reactorsRequest: ReactorsRequest?
    /// A reactor whose profile opens once the reactors sheet has finished dismissing.
    @State private var pendingReactorProfile: UserID?
    /// The `@handle` being looked up after a tap, or nil. Taps while one is in flight are dropped,
    /// so a slow lookup cannot push the same profile twice.
    @State private var tappedMention: Username?
    /// Emoji this OS build can't draw, kept out of the strip and the picker's Frequently Used row.
    @State private var undrawableEmoji: Set<String> = []
    /// The catalog's first category, in catalog order, that fills the strip after the recents.
    @State private var stripCatalog: [String] = []

    /// Where the title starts: clear of the back button.
    private static let titleLeadingInset: CGFloat = 72
    /// Where the title ends: the bar's trailing margin, since nothing sits on that side.
    private static let titleTrailingInset: CGFloat = 16

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
        }
    }

    /// The tip DM counterpart, when this conversation is a tip DM.
    private var tipCounterpart: ConversationMember? {
        if let conversationID,
           let conversation = conversationController.conversation(withID: conversationID),
           conversation.type == .tipDm {
            return conversation.counterpart(excluding: conversationController.selfUserID)
        }
        return nil
    }

    /// Who Send Cash pays: the tip counterpart in a tip DM, the chat itself in
    /// a group, the synced address-book contact when there is one, otherwise a
    /// target built from the counterpart's shared phone number so a chat with a
    /// non-contact can still receive cash. `nil` when none of those resolve.
    private var sendTarget: SendTarget? {
        if let contact, tipCounterpart == nil {
            return .contact(contact)
        }
        guard let conversationID else { return nil }
        return SendTarget(
            conversation: conversationController.conversation(withID: conversationID),
            dmChatID: conversationID.data,
            selfUserID: conversationController.selfUserID
        )
    }

    /// For a tip DM, all counterpart taps open the profile screen — even when
    /// the counterpart is also an address-book contact. A group has no counterpart, so the same
    /// taps open the chat's own profile instead.
    private var profileTapAction: (() -> Void)? {
        if let group = groupConversation {
            return {
                Analytics.groupInfoOpened(
                    memberCount: group.rosterSummary.memberCount,
                    isMember: conversationController.isMember(of: group)
                )
                router.push(.chatProfile(group.id, origin: .chat))
            }
        }
        guard let userID = tipCounterpart?.userID else { return nil }
        return { router.push(.userProfile(userID, origin: .directMessage)) }
    }

    /// Tapping a face in the gutter opens that person's profile — the same screen the counterpart's
    /// own card opens in a DM.
    private func openAuthorProfile(_ userID: UserID) {
        router.push(.userProfile(userID, origin: .groupMember))
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
        if let conversationID {
            return conversationController.displayName(forConversationID: conversationID)
        }
        return contact?.displayName ?? ConversationController.fallbackCounterpartName
    }

    /// The chat's participation rules weighed against the signed-in user: what the bottom of the
    /// screen draws, and whether the transcript is readable at all. `.open` for a chat with no rules.
    ///
    /// Not limited to groups: the server sends rules on some DMs too — the Flipcash account's DM
    /// carries a `never` speaker rule — and a DM participant is always a member, so its speaker
    /// rules close the composer the same way a group's do.
    ///
    /// Recomputed on each observation tick rather than cached, so a balance that crosses the
    /// requirement — or a rate that finally loads — opens the chat without a reopen.
    /// DMs and members fetch web previews as they draw; anyone else, or a chat whose record has not
    /// loaded yet, waits for the chip.
    private var webPreviewMode: WebLinkPreviewMode {
        guard let conversationID,
              let conversation = conversationController.conversation(withID: conversationID),
              conversationController.isMember(of: conversation)
        else { return .tapToLoad }
        return .automatic
    }

    private var gate: ConversationGatePresentation {
        guard let conversationID,
              let conversation = conversationController.conversation(withID: conversationID)
        else {
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
        return conversationController.conversation(withID: conversationID) == nil
    }

    /// The rule verdicts behind ``gate``.
    private var gateVerdicts: ConversationGate {
        guard let conversationID,
              let conversation = conversationController.conversation(withID: conversationID)
        else { return .open }
        return conversationGate(
            session: session,
            rules: conversation.rules,
            creator: conversation.creator,
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
        groupConversation?.rosterSummary.peopleCount
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

    /// The mints the gate's copy has to name: the requirement's, when it names one.
    private var gateMints: [PublicKey] {
        gateMint.map { [$0] } ?? []
    }

    /// Ticker for the requirement the panel names, once its metadata lands.
    private var gateMintName: String? { gateMint.flatMap { mintNames[$0] } }

    /// How much more the gate's minimum asks the user to hold, for the panel's Buy button.
    private var gateShortfall: FiatAmount? {
        let requirement: ConversationGateRequirement
        switch gate {
        case .open, .undetermined, .join:   return nil
        case .blocked(let r), .readOnly(let r): requirement = r
        }
        switch requirement {
        case .minimumBalance(let amount, let mint):
            return balanceShortfall(of: amount, mint: mint, holdings: session, rates: ratesController.cachedRates)
        case .staff, .never, .creator, .unsupported:
            return nil
        }
    }

    private static func mint(of requirement: ConversationGateRequirement) -> PublicKey? {
        switch requirement {
        case .minimumBalance(_, let mint):  mint
        case .staff, .never, .creator, .unsupported:  nil
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
            items: (waitedForLinkPreviews || sessionContainer.linkCardMemo.isLoaded) ? (coordinator?.items ?? []) : [],
            // Paging history for a chat the server hasn't created yet fetches
            // against an id it doesn't know and error-reports.
            onReachTop: { if pagesHistory { coordinator?.reachedTop() } },
            onRetry: retry,
            onCashCardTap: openCurrencyInfo,
            onOpenURL: openLink,
            onMentionTap: openMention,
            onShareProfile: shareProfile,
            ownProfile: ownProfile,
            onLinkCardTap: openLinkCard,
            linkCardSource: sessionContainer.linkCardFeed,
            webPreviewMode: webPreviewMode,
            onEncryptionMarkerTap: { isShowingEncryptionInfo = true },
            onAuthorTap: openAuthorProfile,
            onMessageAction: handleMessageAction,
            onQuoteTap: jumpToQuote,
            onMessagesSeen: markSeen,
            reportsReads: reportsReads(gate: gate),
            onReactionTap: toggleReaction,
            onReactionLongPress: openReactors,
            onReactionAdd: openReactionPicker,
            reactionStripEntries: reactionStripEntries,
            onReactionStripSelect: toggleReaction,
            onReactionStripAdd: openReactionPicker,
            showsSendCash: sendTarget != nil,
            conversationID: conversationID,
            symbol: ratesController.balanceCurrency.compactSymbol,
            onSendCash: sendCash,
            conversationController: conversationController,
            barModel: barModel,
            composer: composer,
            editingStableID: composer.editingStableID,
            focusOnAppear: openKeyboard,
            gate: gate,
            // A viewer the gate refuses is refused the read too, so a blocked chat they have no
            // history of has nothing under its blur. The shapes stand in for what they are not
            // allowed to see —
            // which is why this reads `withholdsTranscript` and not `obscuresTranscript`: a chat
            // whose rules haven't landed yet is blurred without yet refusing anything.
            // Also stands in while an empty transcript's first load is out, so a chat with nothing
            // cached opens on the placeholder and paints once with its history.
            showsGatePlaceholder: (gate.withholdsTranscript || !didInitialRead) && (coordinator?.items.isEmpty ?? true),
            gateMintName: gateMintName,
            gateShortfall: gateShortfall,
            onGateAddFunds: addFunds,
            onGateJoin: joinChat,
            isJoiningChat: isJoiningChat,
            mentions: mentions,
            authorAvatars: authorAvatars,
            acceptsMedia: acceptsMedia,
            onCameraCapture: stageCapturedPhoto,
            onPhotosAdded: stageAddedPhotos,
            mintMediaURL: mintMediaURL,
            mediaBlobDecrypt: mediaBlobDecrypt,
            onMediaTap: openMediaViewer
        )
    }

    /// Whether the chat takes photos: any chat this device has a record of, encrypted or not. False
    /// until the record loads, so the menu never offers a photo before the chat is known.
    private var acceptsMedia: Bool {
        ChatMediaGate.acceptsMedia(conversationID.flatMap(conversationController.conversation(withID:)))
    }

    /// Uploads chat photos on behalf of the signed-in owner, encrypted for the chat when it encrypts.
    private var mediaUploader: ChatMediaUploader {
        let controller = conversationController
        let conversationID = conversationID
        var uploader = ChatMediaUploader(blob: SessionChatMediaBlobStore(session: session, flipClient: container.flipClient))
        uploader.seal = {
            guard let conversationID else { return nil }
            return try await controller.photoSeal(for: conversationID)
        }
        return uploader
    }

    /// Stages photos added from the photo card in the order they were selected, returning the chip
    /// the first became when its image was already loaded. The rest stage as they finish loading.
    private func stageAddedPhotos(
        _ items: [PhotosPickerItem],
        preloader: ChatPhotoPreloader<PhotosPickerItem>
    ) -> ComposerChip.ID? {
        ChatPhotoStaging.stageAdded(
            items,
            into: composer,
            uploader: mediaUploader,
            loaded: preloader.loadedImage(for:),
            load: preloader.image(for:)
        ).handOff
    }

    /// Stages a photo taken with the inline camera, returning the chip it became.
    private func stageCapturedPhoto(_ capture: ChatCameraCapture) -> ComposerChip.ID? {
        composer.stageChip(image: capture.image, preview: capture.preview, uploader: mediaUploader)?.id
    }

    /// Opens a tapped photo full screen, zooming out of its row, with share through the system sheet.
    /// The transcript only hands over a request for a photo the viewer may see, so nothing here can
    /// open or download a BlurHash-only one.
    private func openMediaViewer(_ request: ChatMediaViewerRequest) {
        guard var presenter = UIApplication.shared.currentKeyWindow?.rootViewController else { return }
        while let presented = presenter.presentedViewController {
            presenter = presented
        }
        let viewer = ChatMediaViewerController(request: request) { image in
            ShareSheet.present(activityItems: [image]) { _ in }
        }
        presenter.present(viewer, animated: true)
    }

    /// Mints a download URL for a photo in this chat, read through the chat's access context.
    /// Decrypts this chat's end-to-end encrypted photos with the key its messages open with.
    private var mediaBlobDecrypt: () async -> ChatMediaURLResolver.BlobDecrypt? {
        { [controller = conversationController, conversationID] in
            guard let conversationID else { return nil }
            return await controller.mediaBlobDecrypt(for: conversationID)
        }
    }

    private var mintMediaURL: (BlobID) async throws -> URL? {
        { [flipClient = container.flipClient, owner = session.ownerKeyPair, conversationID] blobID in
            guard let conversationID else { return nil }
            return try await flipClient.blobDownloadURL(blobID: blobID, owner: owner, accessContext: .chatMessage(conversationID))
        }
    }

    var body: some View {
        // The UIKit transcript hosts the bar internally and owns all keyboard handling, so there's
        // no SwiftUI `.safeAreaInset` bar here.
        //
        // The gate is resolved once here and passed down. It has to be: the transcript calls
        // `onReachTop` on every scroll frame it spends near the top, and reading `gate` re-evaluates
        // the chat's rules against the balance and the rate table each time.
        let gate = self.gate
        let pagesHistory = !gate.obscuresTranscript
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
        .overlay(alignment: .top) {
            if let reactionToastText {
                ToastLabel(reactionToastText)
                    .padding(.top, 8)
                    .allowsHitTesting(false)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.default, value: reactionToastText)
        .onChange(of: conversationController.reactions.error) { _, _ in
            scheduleReactionErrorDismissal()
        }
        .sheet(item: $reactionPickerRequest) { request in
            EmojiPickerSheet(
                recents: sessionContainer.recentReactions.row(limit: RecentReactionsStore.pickerRowLimit, undrawable: undrawableEmoji)
            ) { emoji in
                if let conversationID {
                    conversationController.reactions.toggle(emoji, messageID: request.messageID, in: conversationID)
                }
                reactionPickerRequest = nil
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $reactorsRequest, onDismiss: {
            guard let userID = pendingReactorProfile else { return }
            pendingReactorProfile = nil
            router.push(.userProfile(userID, origin: groupConversation == nil ? .directMessage : .groupMember))
        }) { request in
            ReactorsSheet(pills: request.pills, model: request.model) { userID in
                pendingReactorProfile = userID
                reactorsRequest = nil
            }
        }
        // Tied to the screen, so leaving mid-lookup cancels the push rather than landing a profile
        // on whatever screen is up by then. The lookup itself carries on and warms the memo.
        .task(id: tappedMention) {
            guard let username = tappedMention else { return }
            let lookup = await sessionContainer.linkCardFeed.person(.username(username))
            guard !Task.isCancelled else { return }
            tappedMention = nil
            open(MentionDestination.destination(for: lookup, counterpart: tipCounterpart?.userID), for: username)
        }
        .ignoresSafeArea(.keyboard)
        // Extend the transcript under the navigation bar so content scrolls beneath it — that's
        // what lets the iOS 26 toolbar scroll-edge effect materialize. The collection view keeps a
        // top content inset (it adjusts for the safe area) so messages stay readable below the bar.
        //
        // The bottom too, so the transcript runs under the home indicator and the composer's fade
        // reaches the display's bottom edge. The screen still holds the bar clear of the home
        // indicator itself — see `KeyboardFloor`.
        .ignoresSafeArea(.container, edges: [.top, .bottom])
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
                        // Too wide to centre, the bar lays the item out from just past the back
                        // button, so the width alone sets where it ends; no offset is needed.
                        width: max(navBarWidth - Self.titleLeadingInset - Self.titleTrailingInset, 0),
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
        .task {
            await sessionContainer.linkCardMemo.awaitLoaded()
            waitedForLinkPreviews = true
        }
        .task {
            // The probe runs once per OS build; after that this is a cached read.
            guard let contents = try? await EmojiCatalog.shared.load() else { return }
            undrawableEmoji = await UndrawableEmojiCache.shared.undrawable(in: contents.emoji)
            let first = contents.categories.first
            stripCatalog = contents.emoji
                .filter { $0.category == first && !undrawableEmoji.contains($0.emoji) }
                .map(\.emoji)
        }
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
        // One picker per visit, so its suggestion fetch runs once per visit.
        .onChange(of: groupConversation?.id, initial: true) { _, groupID in
            mentions = groupID.map { MentionPickerModel(source: sessionContainer.rosterSearch, chatID: $0) }
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
        // Fetch the signed-in user's own avatar for a shared-profile widget that names them.
        .task(id: sessionContainer.session.profile?.profilePicture?.thumbnailBlobID) {
            guard let picture = sessionContainer.session.profile?.profilePicture else { return }
            await sessionContainer.profileAvatars.load(userID: sessionContainer.session.userID, picture: picture)
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
        .sheet(isPresented: $isShowingEncryptionInfo) {
            E2eeLearnMoreSheet(kind: .dm, isPresented: $isShowingEncryptionInfo)
        }
        .fullScreenCover(item: $messageReport) { report in
            NavigationStack {
                ReportFlowScreen(
                    target: .message(chatID: report.chatID, messageID: report.messageID)
                )
            }
        }
        .background {
            // Measure the bar width so the title item can be sized to fill it past the back
            // button — the system toolbar won't honor maxWidth on a principal item, so an explicit
            // width is the only way to let the avatar + name left-align across the bar.
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
        .task(id: conversationID) {
            guard let conversationID else { return }
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
        .onChange(of: gate, initial: true) { _, gate in
            reportGateShown(gate)
        }
        .onChange(of: gate.obscuresTranscript) { _, obscures in
            // The opening task read the gate it started with, which for a chat reached by link or
            // push is `.undetermined`: a non-member the rules admit, or a balance that crosses the
            // requirement mid-screen, lifts the blur without re-running it. A join loads for itself.
            guard !obscures, !didInitialRead, !isJoiningChat, let conversationID else { return }
            Task { await loadTranscript(for: conversationID) }
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
        // rather than waiting out the debounce. The idle-stop task suspends with the app, so leaving
        // the foreground stops typing now; `AppDelegate` holds the app awake until it is sent.
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else { return }
            saveDraft(flushing: true)
            if let conversationID {
                conversationController.stopSelfTyping(in: conversationID)
            }
        }
        .onDisappear {
            saveDraft(flushing: true)
            if let conversationID {
                conversationController.flushReadPointer(in: conversationID)
            }
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
        .userActivity(AppUserActivity.openChat, isActive: conversationID != nil) { activity in
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
            // A report names the message, not the chat and not the writer: a chat-level report from
            // here would name a DM id this client derived, and the server has never been told about
            // that one.
            guard let conversationID else { return }
            messageReport = MessageReportRequest(id: stableID, chatID: conversationID, messageID: message.id)
        }
    }

    /// The transcript's own `ChatMessage` for a row, by its stable id — what the reaction handlers
    /// need (pills, `canReact`), as opposed to `handleMessageAction`'s `ConversationMessage` lookup.
    private func chatMessage(withStableID stableID: String) -> ChatMessage? {
        for item in (coordinator?.items ?? []) {
            if case .message(let message) = item, message.id == stableID {
                return message
            }
        }
        return nil
    }

    /// Toggles `emoji` on the row, whichever way it is not currently showing — the same call a pill
    /// tap and a strip selection both make.
    private func toggleReaction(_ stableID: String, emoji: String) {
        guard let conversationID, let messageID = coordinator?.loader.messages.first(where: { $0.stableID == stableID })?.id else { return }
        conversationController.reactions.toggle(emoji, messageID: messageID, in: conversationID)
    }

    /// Opens the reactors sheet for the message. It lists everyone, so which pill was pressed doesn't matter.
    private func openReactors(_ stableID: String, emoji _: String) {
        guard let message = chatMessage(withStableID: stableID), !message.reactions.isEmpty,
              let messageID = coordinator?.loader.messages.first(where: { $0.stableID == stableID })?.id else { return }
        guard let conversationID else { return }
        // Built and started here rather than in the sheet, so the first pages load while the sheet
        // is still sliding up.
        let model = ReactorsListModel(
            source: FlipClientReactorsSource(client: container.flipClient, owner: session.ownerKeyPair),
            conversationID: conversationID,
            messageID: messageID,
            emojis: message.reactions.map(\.emoji)
        )
        Task { await model.loadMoreIfNeeded() }
        reactorsRequest = ReactorsRequest(id: stableID, pills: message.reactions, model: model)
    }

    /// Opens the picker sheet for the row's trailing "+" or the strip's own "+".
    private func openReactionPicker(_ stableID: String) {
        guard let messageID = coordinator?.loader.messages.first(where: { $0.stableID == stableID })?.id else { return }
        reactionPickerRequest = ReactionPickerRequest(id: stableID, messageID: messageID)
    }

    /// The long-press strip's content: the six defaults, always first and in place, then the user's
    /// most used, then the row's own reactions, then the start of the catalog, filtered to what the
    /// current OS build can draw. Empty suppresses the strip.
    private func reactionStripEntries(for message: ChatMessage) -> [ReactionStrip.Entry] {
        let fixed = RecentReactions.defaults.filter { !undrawableEmoji.contains($0) }
        let mostUsed = sessionContainer.recentReactions
            .row(limit: fixed.count + RecentReactionsStore.stripLimit, undrawable: undrawableEmoji)
            .filter { !fixed.contains($0) }
            .prefix(RecentReactionsStore.stripLimit)
        let recents = fixed + mostUsed
        return ReactionStrip.filled(
            ReactionStrip.entries(recents: recents, selfReactions: message.selfReactions),
            from: stripCatalog,
            limit: RecentReactionsStore.stripFillLimit
        )
    }

    /// Maps a reaction failure to the copy the spec calls for. `.reactionFailed` covers both the
    /// network path and a server rejection that isn't the reaction-type cap.
    private func reactionErrorCopy(_ error: ReactionError) -> String {
        switch error {
        case .reactionFailed:
            "Couldn't add reaction"
        case .tooManyReactionTypes:
            "This message has the maximum number of reactions"
        }
    }

    /// The toast text for the controller's current `reactions.error`, or nil — read by `chrome`'s
    /// overlay, the same "just show it, no confirmation" treatment as other best-effort chat actions.
    private var reactionToastText: String? {
        conversationController.reactions.error.map(reactionErrorCopy)
    }

    /// Clears the error a beat after it's shown, so the toast dismisses itself rather than sticking
    /// until the next reaction attempt.
    private func scheduleReactionErrorDismissal() {
        guard conversationController.reactions.error != nil else { return }
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            conversationController.reactions.error = nil
        }
    }

    /// The message a report is being filed against, so the sheet can be presented by item rather
    /// than from a loose boolean and a second piece of state that could disagree with it.
    private struct MessageReportRequest: Identifiable {
        /// The transcript row's stable id — already unique per row, and already a `String`.
        let id: String
        let chatID: ConversationID
        let messageID: MessageID
    }

    private struct ReactionPickerRequest: Identifiable {
        let id: String
        let messageID: MessageID
    }

    private struct ReactorsRequest: Identifiable {
        let id: String
        let pills: [ReactionPill]
        let model: ReactorsListModel
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
        case .media(let attachments, let caption):
            (
                ChatQuote.snippet(forText: ChatMediaStrings.quoteSnippet(caption: caption)),
                .media(thumbnailBlobID: message.redacted ? nil : attachments.first?.blobID, sealed: attachments.first?.sealed)
            )
        case .deleted:
            (ChatQuote.deletedSnippet, .unavailable)
        case .widget(.shareProfile):
            (ChatQuote.sharedProfileSnippet, .text)
        case .encrypted, .widget(.unrecognized):
            (ChatQuote.unavailableSnippet, .unavailable)
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
        case .tip:              .sendTips
        case .contact, .group:  .giveCash
        }
        let rate = ratesController.rateForBalanceCurrency()
        if let dialog = giveCashGate(session: session, rate: rate).blockingDialog(router: router, addMoneySource: .chat, context: context) {
            session.dialogItem = dialog
            return
        }
        router.presentSendAmount(sendTarget)
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
            Analytics.tokenInfoOpened(from: .openedFromChat, mint: fiat.mint)
            router.push(.currencyInfo(fiat.mint))
        case .text, .deleted, .encrypted, .widget, .media:
            break
        }
    }

    /// The gate panel's CTA: buys the mint the requirement names, or opens add-cash when there is no
    /// one token to buy — a requirement spanning every holding, and a dollar-token one, which is
    /// satisfied by adding cash rather than by swapping into the thing the cash already is. Both
    /// routes leave the chat on the stack, so satisfying the requirement returns to an ungated screen.
    private func addFunds() {
        guard let gateMint, gateMint != .usdf else {
            Analytics.groupGateFundingTapped(method: .addCash, gateMint: gateMint)
            router.presentAddMoney(.general, source: .chat)
            return
        }
        guard canPayForGateShortfall(buying: gateMint) else {
            Analytics.groupGateFundingTapped(method: .addCash, gateMint: gateMint)
            router.presentAddMoney(.buyCurrency, source: .buyShortfall)
            return
        }
        Analytics.groupGateFundingTapped(method: .buyToken, gateMint: gateMint)
        router.push(.buyCurrency(gateMint))
    }

    /// Whether one held balance can pay for the gap, as the buy flow pays from a single source and
    /// can't spend the token being bought. With no gap to state, any spendable balance will do.
    private func canPayForGateShortfall(buying mint: PublicKey) -> Bool {
        let rate = ratesController.rateForBalanceCurrency()
        let sources = session.balances(for: rate).filter {
            $0.stored.mint != mint && $0.exchangedFiat.hasDisplayableValue()
        }
        guard let needed = gateShortfall?.converted(to: .usd, rates: ratesController.cachedRates) else {
            return !sources.isEmpty
        }
        return sources.contains { $0.exchangedFiat.usdfValue >= needed }
    }

    /// Sends `Group: Gate Shown` the first time this visit draws a join gate. A gate that is
    /// still `.undetermined` waits for its answer; a member's read-only panel isn't a join gate.
    private func reportGateShown(_ gate: ConversationGatePresentation) {
        guard !didReportGate, let group = groupConversation else { return }
        let access: GroupAccess
        switch gate {
        case .join:                          access = .eligible
        case .blocked:                       access = .blocked
        case .open, .undetermined, .readOnly: return
        }
        didReportGate = true
        Analytics.groupGateShown(
            access: access,
            gateMint: group.rules.gateMint,
            memberCount: group.rosterSummary.memberCount
        )
    }

    /// Moves the READ pointer past a message the transcript reports on screen.
    private func markSeen(_ messageID: MessageID) {
        guard let conversationID else { return }
        conversationController.advanceReadPointer(to: messageID, in: conversationID)
    }

    /// Whether rows on screen count as read: only while the app is in front, since UIKit keeps
    /// applying transcript updates in the background, and never under the gate's blur.
    private func reportsReads(gate: ConversationGatePresentation) -> Bool {
        scenePhase == .active && !gate.obscuresTranscript
    }

    /// Everything the screen does once the gate lets it read. Factored out of the opening `.task`
    /// because a join opens the gate mid-screen, which does not re-run that task.
    private func loadTranscript(for conversationID: ConversationID) async {
        // The newest page IS the fresh state and seats the event-log cursor to head, so opening a
        // chat needs no separate catch-up. Missed-while-open windows are reconciled by the
        // foreground / reconnect / live-gap triggers instead.
        await conversationController.loadMessages(for: conversationID)
        await conversationController.refreshReactions(for: conversationID)
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
        // Read before the join, which seats a roster that already counts the viewer.
        let memberCount = groupConversation?.rosterSummary.memberCount ?? 0
        let gated = groupConversation?.rules?.listener.isEmpty == false
        Task {
            defer { isJoiningChat = false }
            do {
                try await conversationController.join(conversationID: conversationID)
                Analytics.groupJoined(error: nil, memberCount: memberCount, gated: gated)
                await loadTranscript(for: conversationID)
            } catch {
                Analytics.groupJoined(error: error, memberCount: memberCount, gated: gated)
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
        ChatLinkOpener(
            openDeepLink: { container.deepLinkController.open($0) },
            openExternally: { ExternalLinkOpener(session: session).open($0) }
        ).open(url)
    }

    /// Opens the share sheet on the widget's person, with the public link their own You tab shares.
    private func shareProfile(_ card: LinkCard.User, displayName: String?) {
        let item = TipCodeShareItem.profile(url: card.url, displayName: displayName)
        ShareSheet.present(activityItem: item) { _ in }
    }

    /// The session profile as a card, for a widget naming the viewer's own handle. Read from `body`,
    /// so a picture landing redraws it. Nil until the profile has a claimed handle.
    private var ownProfile: OwnProfileCard? {
        guard let profile = sessionContainer.session.profile, let username = profile.username else { return nil }
        let userID = sessionContainer.session.userID
        return OwnProfileCard(
            username: username,
            resolved: LinkCard.User.Resolved(
                userID: userID,
                isOwn: true,
                displayName: profile.displayName ?? "",
                handle: username.handle,
                joined: nil,
                imageData: sessionContainer.profileAvatars.data(for: userID),
                blurHash: profile.profilePicture?.thumbnailBlurhash
            )
        )
    }

    /// Looks up a tapped `@handle` and opens whoever it names. Resolved on tap rather than as the
    /// message maps: a transcript full of handles would otherwise cost a lookup per handle for
    /// people nobody taps.
    private func openMention(_ username: Username) {
        guard tappedMention == nil else { return }
        tappedMention = username
    }

    private func open(_ destination: MentionDestination, for username: Username) {
        switch destination {
        case .ownTipCard:
            router.showOwnTipCard()
        case .profile(let userID, let origin):
            router.push(.userProfile(userID, origin: origin))
        case .noSuchAccount:
            session.dialogItem = .info(title: "No Such Account", subtitle: "Nobody has claimed \(username.handle)")
        case .lookupFailed:
            session.showConnectionFailure(.error(
                title: "Couldn't Open Profile",
                subtitle: "Please check your connection and try again"
            ))
        }
    }

    /// Where a tapped link card lands, which is not the same place for every kind.
    ///
    /// A cash card goes out through the deep-link path its URL would have taken — claiming is that
    /// path's job and the card has no part in it — unless the viewer can't chat here. A
    /// group card and a token card push onto this chat's own stack instead, so back returns to the
    /// conversation that held the link: the deep-link handler's `.chat` and `.token` routes both
    /// replace the stack. The pushed group screen gates itself, offering the join or the buy, so the
    /// card never joins from here.
    private func openLinkCard(_ card: LinkCard, messageStableID: String) {
        switch card {
        case .cash(let cash):
            switch gate.cashCollectionBlock(allowsReactions: gateVerdicts.allowsReactions) {
            case nil:
                break
            case .notMember:
                session.dialogItem = .info(title: "Join to Collect", subtitle: "Join this chat to collect cash sent in it.")
                return
            case .cannotChat:
                session.dialogItem = .info(title: "Chat to Collect", subtitle: "Only people who can chat here can collect cash sent in it.")
                return
            }
            noteCashLinkTap(entropy: cash.entropy, messageStableID: messageStableID)
            openLink(card.url)
        case .web:
            // Through the same "You're Leaving Flipcash" path as a tap on the link text.
            openLink(card.url)
        case .group(let group):
            // A link to the chat already on screen has nowhere to go.
            guard group.chatID != conversationID else { return }
            Analytics.groupInviteFollowed(source: .chatCard)
            router.push(.tipConversation(group.chatID))
        case .token(let token):
            Analytics.tokenInfoOpened(from: .openedFromChat, mint: token.mint)
            router.push(.currencyInfo(token.mint))
        case .user:
            // The card is its own button, disabled with no account behind it, so a tap always
            // finds the lookup's answer here.
            guard case .user(.resolved(let user))? = sessionContainer.linkCardFeed.known(card) else { return }
            if user.isOwn {
                router.showOwnTipCard()
                return
            }
            // A link to the person this DM is already with has nowhere to go.
            guard user.userID != tipCounterpart?.userID else { return }
            // Their profile, as a tapped `@handle` opens it; its Message button leads on to the DM.
            router.push(.userProfile(user.userID, origin: .mention))
        }
    }

    /// Arms the thank-you for a voucher someone else sent, in a chat the viewer can post to. The
    /// reply goes out only if the claim this tap starts collects — see ``CashLinkClaimReplies``.
    private func noteCashLinkTap(entropy: String, messageStableID: String) {
        guard !gate.replacesComposer,
              let coordinator,
              let message = coordinator.loader.messages.first(where: { $0.stableID == messageStableID }),
              !message.isFromSelf(conversationController.selfUserID)
        else { return }
        coordinator.claimReplies.tapped(entropy: entropy, messageID: message.id)
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
                prefetchWebCards: { [linkCardFeed = sessionContainer.linkCardFeed] in linkCardFeed.prefetch($0) }
            )
        }
    }


}

// MARK: - Title -

/// Avatar + name, left-aligned in the principal slot and sized to run from the back button to the
/// bar's trailing margin (the system toolbar won't honor maxWidth on a principal item). When
/// `onTap` is non-nil the whole item becomes a button that opens the counterpart's contact card or
/// profile screen.
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
        }
        .frame(width: width, alignment: .leading)
    }
}

