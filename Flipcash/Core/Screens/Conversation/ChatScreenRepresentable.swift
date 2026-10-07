//
//  ChatScreenRepresentable.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import PhotosUI
import SwiftUI
import UIKit
import FlipcashCore
import FlipcashUI

/// Hosts the fully-UIKit chat (transcript + bar) inside SwiftUI. SwiftUI supplies the already-mapped
/// messages and hosts the single bottom bar — Send Cash beside the composer — pinned to the keyboard
/// layout guide. All scroll, keyboard, and flow-under behavior lives in the UIKit screen.
struct ChatScreenRepresentable: UIViewControllerRepresentable {

    let items: [ChatItem]
    /// Fired when the transcript nears the top — the owner fetches the next older page (the
    /// transcript preserves scroll offset across the prepend). This is the incremental
    /// reverse-infinite paging that the UIKit rebuild exists to enable.
    let onReachTop: () -> Void
    /// Fired when the user taps a failed outgoing row; the argument is the message's stable id (its
    /// client message id). The owner re-sends it.
    let onRetry: (String) -> Void
    /// Fired when the user taps a cash card; the argument is the message's stable id. The owner opens
    /// that token's currency info.
    let onCashCardTap: (String) -> Void
    /// Fired when the user taps a URL in a message. The owner routes it through the deep-link handler,
    /// falling back to the system browser.
    let onOpenURL: (URL) -> Void
    /// Fired when the user taps an `@handle` in a message. The owner looks the handle up and opens
    /// that person's profile.
    let onMentionTap: (Username) -> Void
    /// Fired when the Share button on a shared-profile widget is tapped, with the name it shows once resolved.
    let onShareProfile: (LinkCard.User, String?) -> Void
    let ownProfile: OwnProfileCard?
    /// Fired when the user taps the card drawn in place of a link, with the whole card and the
    /// stable id of the message it came on. The owner decides where it lands, which differs by kind.
    let onLinkCardTap: (LinkCard, String) -> Void
    /// Where a link card looks its link up — see ``LinkCardFeed``. Container-scoped, so it outlives
    /// both this view and the rows that subscribe to it.
    let linkCardSource: any LinkCardSource
    /// Fired when the user taps the "Encrypted" marker above a DM's first encrypted message.
    let onEncryptionMarkerTap: () -> Void
    /// Fired when the user taps an author's face in a group's gutter, with that author's user id.
    let onAuthorTap: (UserID) -> Void
    /// Fired when a context-menu action is chosen on a row, with the row's stable id. Copy never
    /// arrives here — the transcript puts the text on the pasteboard itself.
    let onMessageAction: (String, MessageCapability) -> Void
    /// Brings the quoted original into the loader's window; the scroll follows here.
    let onQuoteTap: (String) -> Void
    /// Fired with the newest message someone else sent that the reader has had on screen, each time
    /// it moves forward.
    let onMessagesSeen: (MessageID) -> Void
    /// Whether rows on screen count as read right now.
    let reportsReads: Bool
    /// Fired when a reaction pill is tapped: the row's stable id and the toggled emoji.
    let onReactionTap: (String, String) -> Void
    /// Fired when a reaction pill is long-pressed: the row's stable id and emoji, to open the
    /// reactors sheet scoped to it.
    let onReactionLongPress: (String, String) -> Void
    /// Fired when a row's trailing "+" reaction pill is tapped, with the row's stable id.
    let onReactionAdd: (String) -> Void
    /// Supplies the long-press strip's content for a message — see
    /// `ChatScreenViewController.reactionStripEntries`.
    let reactionStripEntries: (ChatMessage) -> [ReactionStrip.Entry]
    /// Fired when the long-press strip's emoji is tapped: the row's stable id and the toggled emoji.
    let onReactionStripSelect: (String, String) -> Void
    /// Fired when the long-press strip's "+" is tapped, with the row's stable id.
    let onReactionStripAdd: (String) -> Void
    let showsSendCash: Bool
    let conversationID: ConversationID?
    let symbol: String
    let onSendCash: () -> Void
    let conversationController: ConversationController
    let barModel: ConversationBarModel
    let composer: ComposerModel
    /// The row an edit is open on, or nil. Passed in rather than read off `composer` inside the
    /// representable so that the owning view's body depends on it — which is what gets
    /// `updateUIViewController` called, and the edit backdrop taken down, when the edit ends.
    let editingStableID: String?
    /// Raise the keyboard when the screen first appears (post-tip open). The UIKit screen focuses
    /// the composer field in `viewDidAppear` — a hosted SwiftUI `@FocusState` never presents the
    /// keyboard across the hosting boundary.
    let focusOnAppear: Bool
    /// Whether the chat's participation rules leave this user anything to type, and whether they
    /// may read at all. Drives the gate panel in place of the bar and the blur over the transcript.
    let gate: ConversationGatePresentation
    /// Whether the gate's decorative shapes are drawn behind the blur — see
    /// ``GatePreviewPlaceholder``. Set for a chat the viewer cannot read and has no history of.
    let showsGatePlaceholder: Bool
    /// Display name of the mint the gate's requirement names, once resolved.
    let gateMintName: String?
    /// Opens the buy or add-cash flow from the gate panel's CTA.
    let onGateAddFunds: () -> Void
    /// Joins the chat from the gate panel's Join button.
    let onGateJoin: () -> Void
    /// Whether a join is in flight; the gate panel's button stops taking taps.
    let isJoiningChat: Bool
    /// The group's mention picker, or `nil` in a DM.
    let mentions: MentionPickerModel?
    /// Avatar bytes for the group's members, keyed by user id. Empty in a DM, and empty for a group
    /// until the pictures download — the rows fall back to a BlurHash, then a monogram.
    let authorAvatars: [UserID: Data]
    /// Whether the chat takes photos; false for an E2EE DM.
    var acceptsMedia: Bool = false
    /// Receives a photo taken with the camera card, which the representable opens over the composer
    /// and closes again once the photo is handed over.
    /// Returns the chip the photo was staged as, which the capture shrinks into.
    var onCameraCapture: (ChatCameraCapture) -> ComposerChip.ID? = { _ in nil }
    /// Receives the photos added from the attach menu's photo card, in the order they were
    /// selected, with the loader already reading them. Returns the chip the first was staged as,
    /// which the card shrinks into, when it could be staged at once.
    var onPhotosAdded: ([PhotosPickerItem], ChatPhotoPreloader<PhotosPickerItem>) -> ComposerChip.ID? = { _, _ in nil }
    /// Mints a signed download URL for a photo in this chat. The transcript's resolver caches what it
    /// returns and never asks for a photo drawn only from its BlurHash.
    var mintMediaURL: (BlobID) async throws -> URL? = { _ in nil }
    /// Decrypts the chat's end-to-end encrypted photo blobs, or nil while its key is unknown.
    var mediaBlobDecrypt: () async -> ChatMediaURLResolver.BlobDecrypt? = { nil }
    /// Fired when the user taps a photo the viewer may see. The owner opens the full-screen viewer.
    var onMediaTap: (ChatMediaViewerRequest) -> Void = { _ in }

    func makeUIViewController(context: Context) -> ChatScreenViewController {
        let barHost = UIHostingController(rootView: bar(coordinator: context.coordinator))
        barHost.view.backgroundColor = .clear
        // The bar's content is pinned to the bottom of this view and overhangs the top while the
        // height constraint catches up, so the overhang has to be allowed to draw.
        barHost.view.clipsToBounds = false
        // The screen places the bar, clear of the keyboard and resting partway into the home
        // indicator's safe area. Left to respect that safe area, the bar pushes its content up by
        // however far it rests into it, past the clip's top edge.
        barHost.safeAreaRegions = []
        let screen = ChatScreenViewController(bar: barHost.view, barController: barHost)
        screen.focusesComposerOnAppear = focusOnAppear
        screen.isTranscriptObscured = gate.obscuresTranscript
        screen.showsGatePlaceholder = showsGatePlaceholder
        screen.barRestingDrop = BarMetrics.compactDrop
        screen.authorAvatars = authorAvatars
        screen.onReachTop = onReachTop
        screen.onRetry = onRetry
        screen.onCashCardTap = onCashCardTap
        screen.onOpenURL = onOpenURL
        screen.onMentionTap = onMentionTap
        screen.onShareProfile = onShareProfile
        screen.ownProfile = ownProfile
        screen.onLinkCardTap = onLinkCardTap
        screen.linkCardSource = linkCardSource
        screen.onMediaTap = onMediaTap
        context.coordinator.mintMediaURL = mintMediaURL
        context.coordinator.mediaBlobDecrypt = mediaBlobDecrypt
        screen.mediaURLResolver = context.coordinator.mediaURLResolver
        screen.pendingMediaImage = { [conversationController] id in
            conversationController.pendingMediaImage(forMessageID: id)
        }
        screen.pendingMediaProgress = { [conversationController] id in
            conversationController.pendingMediaProgress(forMessageID: id)
        }
        screen.onEncryptionMarkerTap = onEncryptionMarkerTap
        screen.onAuthorTap = onAuthorTap
        screen.onMessageAction = keyboardFollowing(onMessageAction, screen: screen)
        screen.onQuoteTap = { [weak screen] stableID in
            onQuoteTap(stableID)
            // The reveal may have to move the loader's anchor first, so the scroll records a
            // pending target when the row is not in the window yet.
            screen?.scrollToMessage(id: stableID)
        }
        screen.onReactionTap = onReactionTap
        screen.onReactionLongPress = onReactionLongPress
        screen.onReactionAdd = onReactionAdd
        screen.reactionStripEntries = reactionStripEntries
        screen.onReactionStripSelect = onReactionStripSelect
        screen.onReactionStripAdd = onReactionStripAdd
        screen.onCancelEdit = { [composer] in composer.endEditing() }
        screen.onMentionRoomChange = { [mentions] room in mentions?.room = room }
        screen.onMessagesSeen = onMessagesSeen
        screen.reportsReads = reportsReads
        screen.update(items: items)
        context.coordinator.barHost = barHost
        context.coordinator.screen = screen
        context.coordinator.lastMessageID = lastMessageID(of: items)
        return screen
    }

    func updateUIViewController(_ screen: ChatScreenViewController, context: Context) {
        // Re-supply the bar with current inputs; SwiftUI diffs it, so the composer's draft and
        // focus survive across updates.
        context.coordinator.barHost?.rootView = bar(coordinator: context.coordinator)
        screen.isTranscriptObscured = gate.obscuresTranscript
        screen.showsGatePlaceholder = showsGatePlaceholder
        screen.barRestingDrop = BarMetrics.compactDrop
        screen.authorAvatars = authorAvatars
        screen.onReachTop = onReachTop
        screen.onRetry = onRetry
        screen.onCashCardTap = onCashCardTap
        screen.onOpenURL = onOpenURL
        screen.onMentionTap = onMentionTap
        screen.onShareProfile = onShareProfile
        screen.ownProfile = ownProfile
        screen.onLinkCardTap = onLinkCardTap
        screen.linkCardSource = linkCardSource
        screen.onMediaTap = onMediaTap
        context.coordinator.mintMediaURL = mintMediaURL
        context.coordinator.mediaBlobDecrypt = mediaBlobDecrypt
        screen.onEncryptionMarkerTap = onEncryptionMarkerTap
        screen.onAuthorTap = onAuthorTap
        screen.onMessageAction = keyboardFollowing(onMessageAction, screen: screen)
        screen.onQuoteTap = { [weak screen] stableID in
            onQuoteTap(stableID)
            // The reveal may have to move the loader's anchor first, so the scroll records a
            // pending target when the row is not in the window yet.
            screen?.scrollToMessage(id: stableID)
        }
        screen.onReactionTap = onReactionTap
        screen.onReactionLongPress = onReactionLongPress
        screen.onReactionAdd = onReactionAdd
        screen.reactionStripEntries = reactionStripEntries
        screen.onReactionStripSelect = onReactionStripSelect
        screen.onReactionStripAdd = onReactionStripAdd
        screen.onCancelEdit = { [composer] in composer.endEditing() }
        screen.onMentionRoomChange = { [mentions] room in mentions?.room = room }
        screen.onMessagesSeen = onMessagesSeen
        screen.reportsReads = reportsReads
        // The backdrop is raised from the menu action itself (see `keyboardFollowing`) because it
        // has to claim the menu's blur before the dismissal fades it; it comes down here, whichever
        // way the edit ended — cancelled, saved, or abandoned by a tap outside.
        if editingStableID == nil {
            screen.endEditSpotlight()
        }

        // Scroll only when the user's *own* message was just appended — a new trailing message id
        // (skipping any trailing receipt) that is from me — and the reader was scrolled up in
        // history. Received messages and prepended history leave the position alone. At the bottom,
        // ChatLayout's keep-at-bottom already follows the append on the batch's own spring, and a
        // second scroll on top of it fights that spring for the same offset.
        let newLastMessage = lastMessage(of: items)
        let newLastMessageID = newLastMessage?.id
        let lastIsOwnMessage = if case .message(let message) = newLastMessage { message.sender == .me } else { false }
        let appendedOwn = newLastMessageID != context.coordinator.lastMessageID && lastIsOwnMessage
        let wasAtBottom = screen.isTranscriptAtBottom
        screen.update(items: items)
        if appendedOwn, !wasAtBottom {
            screen.scrollToBottom(animated: true)
        }
        context.coordinator.lastMessageID = newLastMessageID
    }

    /// Wraps the action handler so the screen follows the action. The menu dismissed the keyboard
    /// to present itself and the composer can't drive it back on its own — a hosted SwiftUI
    /// `@FocusState` doesn't make the field first responder — so only the screen can raise it for an
    /// edit, or hold it down for a delete, whose confirmation sheet it would otherwise cover. Edit
    /// also claims the menu's blur here, while the menu is still up, so the two states share one
    /// backdrop instead of fading one out and another in.
    private func keyboardFollowing(
        _ handler: @escaping (String, MessageCapability) -> Void,
        screen: ChatScreenViewController
    ) -> (String, MessageCapability) -> Void {
        { [weak screen] stableID, action in
            handler(stableID, action)
            switch action {
            case .edit:
                screen?.beginEditSpotlight(for: stableID)
                screen?.focusComposer()
            case .reply:
                screen?.focusComposer()
            // Both raise a sheet over the transcript, so the keyboard goes down first.
            case .delete, .report: screen?.dismissKeyboard()
            case .copy:            break
            }
        }
    }

    private func lastMessage(of items: [ChatItem]) -> ChatItem? {
        items.last { if case .message = $0 { true } else { false } }
    }

    private func lastMessageID(of items: [ChatItem]) -> String? {
        lastMessage(of: items)?.id
    }

    private func bar(coordinator: Coordinator) -> AnyView {
        coordinator.overlayActions = AttachOverlayActions(
            onCash: onSendCash,
            onCamera: { [weak coordinator] in coordinator?.openCard(.camera) },
            onPhotos: { [weak coordinator] in coordinator?.openCard(.photos) },
            onCameraCapture: { [weak coordinator] capture in coordinator?.closeCard { onCameraCapture(capture) } },
            onCameraCancel: { [model = barModel] in model.returnToMenu() },
            onPhotosAdd: { [weak coordinator] items, preloader in coordinator?.closeCard { onPhotosAdded(items, preloader) } },
            onPhotosBack: { [model = barModel] in model.returnToMenu() },
            onAllPhotos: { [weak coordinator] in coordinator?.overlay.handOffToBar() }
        )
        return AnyView(
            ConversationBottomBar(
                showsSendCash: showsSendCash,
                conversationID: conversationID,
                symbol: symbol,
                onSendCash: onSendCash,
                model: barModel,
                composer: composer,
                gate: gate,
                gateMintName: gateMintName,
                onGateAddFunds: onGateAddFunds,
                onGateJoin: onGateJoin,
                isJoiningChat: isJoiningChat,
                mentions: mentions,
                acceptsMedia: acceptsMedia,
                onAttachOpen: { [weak coordinator] items in
                    coordinator?.openAttach(items: items)
                },
                onCamera: { [weak coordinator] in
                    coordinator?.openCard(.camera)
                },
                onCameraCapture: { [weak coordinator] capture in
                    coordinator?.closeCard { onCameraCapture(capture) }
                },
                onCameraCancel: { [model = barModel] in
                    // Back into the panel, with the keyboard left down.
                    model.returnToMenu()
                },
                onPhotos: { [weak coordinator] in
                    coordinator?.openCard(.photos)
                },
                onPhotosAdd: { [weak coordinator] items, preloader in
                    coordinator?.closeCard { onPhotosAdded(items, preloader) }
                },
                onPhotosBack: { [model = barModel] in
                    // Back into the panel, with the keyboard left down.
                    model.returnToMenu()
                },
                // Only a member can aim a reply, so the viewer may see what it quotes.
                quoteThumbnailLocation: { [resolver = coordinator.mediaURLResolver] kind in
                    await resolver.thumbnailLocation(for: kind, canReact: true)
                }
            )
            .environment(conversationController)
            .modifier(
                MeasuredBarHeight { height, accessories in
                    // After the update that measured it, not inside it. Resized inside an animated
                    // update, the host's new size joins that transaction: SwiftUI springs the root
                    // toward it and centres it meanwhile, lifting the whole bar by half the change.
                    DispatchQueue.main.async {
                        coordinator.screen?.setBarHeight(height, accessories: accessories)
                    }
                }
            )
            // Behind the bar and over the transcript, which the bar's host covers while the panel is
            // up: a touch anywhere outside the panel takes it down.
            .background {
                if barModel.attachPanel.isOpen {
                    AttachPanelDismissArea(panel: barModel.attachPanel)
                }
            }
            .modifier(BarOverflowReporting(model: barModel) { [weak coordinator] in coordinator?.screen })
        )
    }

    func makeCoordinator() -> Coordinator { Coordinator(model: barModel, composer: composer) }

    @MainActor final class Coordinator {
        var barHost: UIHostingController<AnyView>?
        weak var screen: ChatScreenViewController?
        let model: ConversationBarModel
        let composer: ComposerModel
        /// Draws the attach panel and cards over the keyboard while the composer keeps focus.
        let overlay: AttachKeyboardOverlay
        /// What the panel and cards drawn over the keyboard hand back, as of the latest render.
        var overlayActions: AttachOverlayActions?

        init(model: ConversationBarModel, composer: ComposerModel) {
            self.model = model
            self.composer = composer
            self.overlay = AttachKeyboardOverlay(model: model)
        }

        /// `+` is opening the panel with `items` as its rows: over the keyboard while it is up and its
        /// window or the field's input view can carry the panel, else with the keyboard taken down.
        func openAttach(items: [AttachMenuItem]) {
            guard let screen, let overlayActions else { return }
            // Sized now, so the card's content is laid out at its final size while the menu is up.
            model.attachCard.measure(screenHeight: screen.view.bounds.height)
            let mode = overlay.begin(screen: screen, items: items, composer: composer, actions: overlayActions)
            switch mode {
            case .keyboardWindow, .inputView:
                break
            case .dismissKeyboard:
                screen.dismissKeyboard()
            }
        }

        /// Puts the camera or photo card up from the panel, over the keyboard if the panel is.
        func openCard(_ content: AttachCard.Content) {
            if overlay.mode == nil {
                screen?.dismissKeyboard()
            }
            model.attachCard.open(content, screenHeight: screen?.view.bounds.height ?? 0)
        }

        /// Takes the card down into the chip `stage` returns, and puts focus back in the field so the
        /// photo can be captioned. The chip waits hidden while the bar lays it out, and the surface
        /// shrinks onto its frame once it has.
        func closeCard(handingOffTo stage: () -> ComposerChip.ID?) {
            let card = model.attachCard
            guard let chipID = stage() else {
                card.animate { card.close() }
                screen?.focusComposer()
                return
            }
            let chip = composer.chips.first { $0.id == chipID }
            card.beginLanding(on: chipID, image: chip.map { $0.preview ?? $0.image })
            screen?.focusComposer()
            // A chip the bar never lays out leaves nothing to land on, so the card goes anyway.
            DispatchQueue.main.asyncAfter(deadline: .now() + ChatMotion.attachCard.duration) {
                guard card.isOpen, card.landingChipID == chipID else { return }
                card.animate({ card.close() }, then: { card.endLanding() })
            }
        }

        var lastMessageID: String?
        /// The latest ``ChatScreenRepresentable/mintMediaURL``, read by the resolver.
        var mintMediaURL: (BlobID) async throws -> URL? = { _ in nil }
        /// The one resolver the transcript and the composer's reply strip share, so a photo is minted
        /// once however many places draw it. Reads ``mintMediaURL`` at fetch time, so a chat created
        /// after this screen opened mints against its real id.
        /// The latest ``ChatScreenRepresentable/mediaBlobDecrypt``, read by the resolver.
        var mediaBlobDecrypt: () async -> ChatMediaURLResolver.BlobDecrypt? = { nil }
        lazy var mediaURLResolver = ChatMediaURLResolver(
            fetch: { [weak self] blobID in
                guard let self else { return nil }
                return try await self.mintMediaURL(blobID)
            },
            decrypt: { [weak self] in
                await self?.mediaBlobDecrypt()
            }
        )
    }
}

/// Reports a hosted bar's measured natural height to the UIKit screen, which drives its height
/// constraint. Take the natural height at the proposed width so the composer can grow to its full
/// multiline height — the hosting controller's intrinsic size mis-measures and lets the composer
/// overflow under the keyboard.
private struct MeasuredBarHeight: ViewModifier {
    /// Receives the height with the cards above the composer row. The clip decides what to do with
    /// a height from the two together, so they arrive as one value from the same layout pass: a card
    /// that opens changes both, and two separate reports would read as growth and then an opening
    /// with nothing left to travel.
    let report: (CGFloat, BarAccessories) -> Void

    func body(content: Content) -> some View {
        content
            .fixedSize(horizontal: false, vertical: true)
            .overlayPreferenceValue(BarAccessoriesKey.self) { accessories in
                // `onGeometryChange`, not a `GeometryReader`: under an animated layout change the
                // reader reports the height the animation starts from and then goes quiet, which
                // leaves the clip short of the content it settles at.
                Color.clear.onGeometryChange(
                    for: BarReport.self,
                    of: { BarReport(height: $0.size.height, accessories: accessories) }
                ) { new in
                    report(new.height, new.accessories)
                }
            }
            // Sit on the host's bottom edge rather than in the middle of it. The two heights are
            // never equal mid-change: SwiftUI ramps the content's own height on its spring while the
            // constraint above chases it on another, and centring turns every point of that gap into
            // half a point of vertical travel for the whole bar. Bottom-aligned, the gap goes
            // somewhere nobody looks — the bar grows and shrinks from the top, which is the edge the
            // reply strip arrives at.
            .frame(maxHeight: .infinity, alignment: .bottom)
    }
}

/// One measurement of the bar: its height and the cards that make it up.
private nonisolated struct BarReport: Equatable, Sendable {
    let height: CGFloat
    let accessories: BarAccessories
}
