//
//  InviteLinksScreen.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import UIKit
import FlipcashUI
import FlipcashCore

/// Manage Invites (frame 2a, node 12844:200): a hosted private group's invite links, Active then
/// Inactive, with sharing, revoking and making new ones. Pushed from the invite sheet and from the
/// profile's ⋯ menu.
struct InviteLinksScreen: View {

    let conversationID: ConversationID

    @Environment(SessionContainer.self) private var sessionContainer
    @Environment(ConversationController.self) private var conversationController
    @Environment(AppRouter.self) private var router

    @State private var links: GroupInviteLinks?
    @State private var selected: GroupInviteLinks.Entry?
    @State private var pendingAction: RowAction?
    @State private var sharing: SharedLink?
    @State private var isMakingLink = false
    @State private var dialogItem: DialogItem?

    var body: some View {
        Background(color: .backgroundMain) {
            if let links, links.loadState == .loaded {
                InviteLinksContent(
                    active: links.active,
                    inactive: links.inactive,
                    currentID: links.current?.id,
                    onSelect: { selected = $0 },
                    onNewLink: { isMakingLink = true }
                )
            } else {
                ProgressView()
                    .tint(Color.textMain)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Invite Links")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: conversationID) {
            let links = links ?? GroupInviteLinks(conversationID: conversationID, service: sessionContainer.inviteLinks)
            self.links = links
            do {
                try await links.load()
            } catch {
                handle(error)
            }
        }
        // Frame 2b. Its choice runs once the sheet is gone, so the share sheet or the revoke
        // confirmation doesn't present over a sheet on its way out.
        .sheet(item: $selected, onDismiss: runPendingAction) { entry in
            InviteLinkActionSheet(
                entry: entry,
                isPresented: isSelecting,
                onShare: { pendingAction = .share(entry.id) },
                onRevoke: { pendingAction = .revoke(entry) }
            )
        }
        // Share Link opens the invite share sheet (1f) on that row's link.
        .fullScreenCover(item: $sharing) { shared in
            if let links {
                ShareToChatsSheet(
                    subject: .inviteLink(conversationID, links, entry: shared.id),
                    isPresented: Binding { sharing != nil } set: { if !$0 { sharing = nil } },
                    onInvited: { _ in }
                )
            }
        }
        .sheet(isPresented: $isMakingLink) {
            if let links {
                NewInviteLinkSheet(isPresented: $isMakingLink, isCreating: links.isCreating) { expiry, limit in
                    await create(expiry: expiry, limit: limit)
                }
            }
        }
        .dialog(item: $dialogItem)
    }

    private var isSelecting: Binding<Bool> {
        Binding(get: { selected != nil }, set: { if !$0 { selected = nil } })
    }

    private var groupName: String? {
        conversationController.conversation(withID: conversationID)?.title
    }

    private enum RowAction {
        case share(InviteID)
        case revoke(GroupInviteLinks.Entry)
    }

    private struct SharedLink: Identifiable {
        let id: InviteID
    }

    private func runPendingAction() {
        guard let action = pendingAction else { return }
        pendingAction = nil
        switch action {
        case .share(let id):
            sharing = SharedLink(id: id)
        case .revoke(let entry):
            dialogItem = InviteLinkDialogs.revoke { Task { await revoke(entry) } }
        }
    }

    private func revoke(_ entry: GroupInviteLinks.Entry) async {
        guard let links else { return }
        do {
            try await links.revoke(entry)
        } catch {
            handle(error)
        }
    }

    /// Makes a link from 2d. Returns whether the sheet may close.
    private func create(expiry: GroupInviteLinks.Expiry, limit: GroupInviteLinks.UseLimit) async -> Bool {
        guard let links else { return false }
        do {
            try await links.create(expiry: expiry, limit: limit)
            return true
        } catch {
            isMakingLink = false
            dialogItem = InviteLinkDialogs.createFailed(error, onManage: {}, onShareGroupLink: shareGroupLink)
            return false
        }
    }

    private func shareGroupLink() {
        ShareSheet.present(activityItems: [GroupInviteShareItem(url: .groupChatInvite(for: conversationID), title: groupName)]) { _ in }
    }

    /// DENIED on load or revoke means the viewer can no longer invite: back to the profile.
    private func handle(_ error: Error) {
        if (error as? ErrorGetChatInvites) == .denied || (error as? ErrorRevokeInvite) == .denied {
            router.popTopmost()
            return
        }
        dialogItem = .error(title: "Something Went Wrong", subtitle: "Please try again")
    }
}

// MARK: - Content -

/// Frames 2a and 2e as plain state, for the screen and its previews.
struct InviteLinksContent: View {

    let active: [GroupInviteLinks.Entry]
    let inactive: [GroupInviteLinks.Entry]
    let currentID: InviteID?
    let onSelect: (GroupInviteLinks.Entry) -> Void
    let onNewLink: () -> Void

    var body: some View {
        if active.isEmpty && inactive.isEmpty {
            empty
        } else {
            VStack(spacing: 0) {
                list
                Button("New Link", action: onNewLink)
                    .buttonStyle(.filled)
                    .padding(.horizontal, InviteLinksMetrics.inset)
                    .padding(.bottom, 16)
                    .accessibilityIdentifier("invite-links-new")
            }
        }
    }

    /// Frame 2e (node 12844:395): a capsule New Link under the message, no bottom button.
    private var empty: some View {
        VStack(spacing: 0) {
            Text("No invite links")
                .font(.appTextMedium)
                .foregroundStyle(Color.textMain)
            Text("Make a link to let people join without waiting for approval.")
                .font(.default(size: 14, weight: .medium))
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
                .padding(.top, 8)
            Button(action: onNewLink) {
                Text("New Link")
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textMain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(InviteLinksMetrics.panel, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 24)
            .accessibilityIdentifier("invite-links-new")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if !active.isEmpty {
                    section("ACTIVE", entries: active, isActive: true)
                }
                if !inactive.isEmpty {
                    section("INACTIVE", entries: inactive, isActive: false)
                }
            }
            .padding(.horizontal, InviteLinksMetrics.inset)
            .padding(.vertical, 12)
        }
    }

    /// A section header over a rounded card of rows, as frame 2a draws them.
    private func section(_ title: String, entries: [GroupInviteLinks.Entry], isActive: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.appTextHeading)
                .foregroundStyle(Color.textSecondary)
                .padding(.horizontal, 16)
            VStack(spacing: 0) {
                ForEach(entries) { entry in
                    let row = InviteLinkRow(entry: entry, isCurrent: entry.id == currentID, isActive: isActive)
                    if isActive {
                        Button { onSelect(entry) } label: { row }
                            .buttonStyle(.plain)
                    } else {
                        row
                    }
                    if entry.id != entries.last?.id {
                        Rectangle()
                            .fill(Color.rowSeparator)
                            .frame(height: 1)
                            .padding(.leading, 16)
                    }
                }
            }
            .background(Color.backgroundRow, in: RoundedRectangle(cornerRadius: Metrics.boxRadius, style: .continuous))
        }
    }
}

private enum InviteLinksMetrics {
    /// Frame 2a's card inset from the screen edge.
    static let inset: CGFloat = 22
    /// The chip and capsule fill (card/panel, white 8%).
    static let panel = Color.white.opacity(0.08)
}

private struct InviteLinkRow: View {

    let entry: GroupInviteLinks.Entry
    let isCurrent: Bool
    /// Inactive rows are dimmed and take no taps.
    let isActive: Bool

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                Text(InviteLinkCopy.created(entry.invite) ?? "")
                    .font(.appTextMedium)
                    .foregroundStyle(isActive ? Color.textMain : Color.textMain.opacity(0.5))
                Text(InviteLinkCopy.rowDetail(entry))
                    .font(.appTextCaption)
                    .foregroundStyle(isActive ? Color.textSecondary : Color.textMain.opacity(0.5))
            }
            .lineLimit(1)
            Spacer(minLength: 0)
            if isCurrent {
                Text("Current")
                    .font(.appTextHeading)
                    .foregroundStyle(Color.textMain)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(InviteLinksMetrics.panel, in: Capsule())
            }
            if isActive {
                Image(systemName: "chevron.right")
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 64)
        .contentShape(Rectangle())
    }
}

// MARK: - New link -

/// Frame 2d (node 12844:334): expiry and use-limit presets, then Create Link.
struct NewInviteLinkSheet: View {

    @Binding var isPresented: Bool
    let isCreating: Bool
    /// Makes the link; returns whether the sheet may close.
    let onCreate: (GroupInviteLinks.Expiry, GroupInviteLinks.UseLimit) async -> Bool

    @State private var expiry: GroupInviteLinks.Expiry = .sevenDays
    @State private var limit: GroupInviteLinks.UseLimit = .unlimited
    @State private var isSubmitting = false

    /// Presented like ``InviteLinkActionSheet`` (2b): the shared partial sheet and its title bar.
    var body: some View {
        PartialSheet(background: .backgroundMain) {
            form
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, bottomPadding)
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 24)

            chips("Expires", options: GroupInviteLinks.Expiry.allCases, selection: $expiry, title: \.title)
                .padding(.bottom, 24)
            chips("Who can join", options: GroupInviteLinks.UseLimit.allCases, selection: $limit, title: \.title)
                .padding(.bottom, 28)

            Button {
                Task {
                    isSubmitting = true
                    defer { isSubmitting = false }
                    if await onCreate(expiry, limit) { isPresented = false }
                }
            } label: {
                ButtonStateLabel("Create Link", state: isSubmitting || isCreating ? .loading : .normal)
            }
            .buttonStyle(.filled)
            .disabled(isSubmitting || isCreating)
            .accessibilityIdentifier("new-invite-link-create")
        }
    }

    private var header: some View {
        ZStack {
            Text("New Invite Link")
                .font(.appBarButton)
                .foregroundStyle(Color.textMain)
            HStack {
                Spacer()
                CloseButton(style: .glass, binding: $isPresented)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var bottomPadding: CGFloat {
        let reserved = UIApplication.shared.currentKeyWindow?.safeAreaInsets.bottom ?? 0
        return max(0, 16 - reserved)
    }

    private func chips<Option: Hashable>(_ heading: String, options: [Option], selection: Binding<Option>, title: KeyPath<Option, String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(heading)
                .font(.default(size: 13, weight: .medium))
                .foregroundStyle(Color.textSecondary)
            SlidingChipPicker(options, selection: selection) { $0[keyPath: title] }
        }
    }
}

// MARK: - Previews -

private let previewNow = Date(timeIntervalSince1970: 1_793_059_200) // Oct 27, 2026
private let previewSelf = UUID()

private func previewEntry(
    daysAgo: Double,
    status: Invite.Status,
    useCount: UInt32,
    maxUses: UInt32 = 0,
    expiresInDays: Double? = nil,
    shareable: Bool = true
) -> GroupInviteLinks.Entry {
    GroupInviteLinks.Entry(
        invite: Invite(
            id: InviteID(data: Data(UUID().uuidString.utf8.prefix(16))),
            conversationID: ConversationID(data: Data(repeating: 1, count: 16)),
            createdBy: previewSelf,
            maxUses: maxUses,
            useCount: useCount,
            createdAt: previewNow.addingTimeInterval(-daysAgo * 86_400),
            expiresAt: expiresInDays.map { previewNow.addingTimeInterval($0 * 86_400) },
            status: status,
            secretEnvelope: nil
        ),
        url: shareable ? URL(string: "https://app.flipcash.com/chat/invite#s=preview") : nil
    )
}

#Preview("2a · Invite links") {
    let current = previewEntry(daysAgo: 0, status: .active, useCount: 0, expiresInDays: 7)
    NavigationStack {
        Background(color: .backgroundMain) {
            InviteLinksContent(
                active: [
                    current,
                    previewEntry(daysAgo: 7, status: .active, useCount: 12),
                    previewEntry(daysAgo: 25, status: .active, useCount: 3, maxUses: 10, shareable: false),
                ],
                inactive: [
                    previewEntry(daysAgo: 27, status: .expired, useCount: 6, expiresInDays: -20),
                    previewEntry(daysAgo: 45, status: .revoked, useCount: 2),
                    previewEntry(daysAgo: 56, status: .exhausted, useCount: 5, maxUses: 5),
                ],
                currentID: current.id,
                onSelect: { _ in },
                onNewLink: {}
            )
        }
        .navigationTitle("Invite Links")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("2e · Empty") {
    NavigationStack {
        Background(color: .backgroundMain) {
            InviteLinksContent(active: [], inactive: [], currentID: nil, onSelect: { _ in }, onNewLink: {})
        }
        .navigationTitle("Invite Links")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("2d · New link") {
    Background(color: .backgroundMain) {
        NewInviteLinkSheet(isPresented: .constant(true), isCreating: false) { _, _ in true }
    }
}
