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

/// Manage Invites (frame 2a, node 12844:209): a hosted private group's invite links, Active then
/// Inactive, with sharing, revoking and making new ones. Pushed from the invite sheet and from the
/// profile's ⋯ menu.
struct InviteLinksScreen: View {

    let conversationID: ConversationID

    @Environment(SessionContainer.self) private var sessionContainer
    @Environment(ConversationController.self) private var conversationController
    @Environment(AppRouter.self) private var router

    @State private var links: GroupInviteLinks?
    @State private var selected: GroupInviteLinks.Entry?
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
        // The native action sheet of frame 2b.
        .confirmationDialog("", isPresented: isSelecting, titleVisibility: .hidden, presenting: selected) { entry in
            if let url = entry.url {
                Button("Share Link") { share(url) }
                Button("Copy Invite Link") { UIPasteboard.general.string = url.absoluteString }
            }
            Button("Revoke Link", role: .destructive) {
                dialogItem = InviteLinkDialogs.revoke { Task { await revoke(entry) } }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $isMakingLink) {
            if let links {
                NewInviteLinkSheet(isCreating: links.isCreating) { expiry, limit in
                    await create(expiry: expiry, limit: limit)
                }
                .presentationDetents([.medium])
                .presentationBackground(Color.backgroundMain)
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

    private func share(_ url: URL) {
        Analytics.groupInviteShared(method: .share)
        ShareSheet.present(activityItems: [GroupInviteShareItem(url: url, title: groupName, kind: .inviteLink)]) { _ in }
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
        VStack(spacing: 0) {
            if active.isEmpty && inactive.isEmpty {
                empty
            } else {
                list
            }
            Button("New Link", action: onNewLink)
                .buttonStyle(.filled)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
                .accessibilityIdentifier("invite-links-new")
        }
    }

    /// Frame 2e.
    private var empty: some View {
        VStack(spacing: 8) {
            Spacer()
            Text("No invite links")
                .font(.appTextLarge)
                .foregroundStyle(Color.textMain)
            Text("Make a link to let people join without waiting for approval.")
                .font(.appTextMedium)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity)
    }

    private var list: some View {
        List {
            if !active.isEmpty {
                Section {
                    ForEach(active) { entry in
                        Button { onSelect(entry) } label: {
                            InviteLinkRow(entry: entry, isCurrent: entry.id == currentID, isActive: true)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    sectionHeader("ACTIVE")
                }
            }
            if !inactive.isEmpty {
                Section {
                    ForEach(inactive) { entry in
                        InviteLinkRow(entry: entry, isCurrent: false, isActive: false)
                    }
                } header: {
                    sectionHeader("INACTIVE")
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .listRowBackground(Color.clear)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.appTextHeading)
            .foregroundStyle(Color.textSecondary)
    }
}

private struct InviteLinkRow: View {

    let entry: GroupInviteLinks.Entry
    let isCurrent: Bool
    /// Inactive rows are dimmed and take no taps.
    let isActive: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(InviteLinkCopy.created(entry.invite) ?? "")
                    .font(.appTextMedium)
                Text(InviteLinkCopy.rowDetail(entry))
                    .font(.appTextCaption)
                    .foregroundStyle(isActive ? Color.textSecondary : Color.textMain.opacity(0.5))
            }
            Spacer()
            if isCurrent {
                Text("Current")
                    .font(.appTextCaption)
                    .foregroundStyle(Color.textMain)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.backgroundRow, in: Capsule())
            }
        }
        .foregroundStyle(isActive ? Color.textMain : Color.textMain.opacity(0.5))
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .listRowBackground(Color.clear)
        .listRowSeparatorTint(Color.rowSeparator)
    }
}

// MARK: - New link -

/// Frame 2d (node 12844:268): expiry and use-limit presets, then Create Link.
struct NewInviteLinkSheet: View {

    let isCreating: Bool
    /// Makes the link; returns whether the sheet may close.
    let onCreate: (GroupInviteLinks.Expiry, GroupInviteLinks.UseLimit) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var expiry: GroupInviteLinks.Expiry = .sevenDays
    @State private var limit: GroupInviteLinks.UseLimit = .unlimited
    @State private var isSubmitting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("New Invite Link")
                .font(.appTextLarge)
                .foregroundStyle(Color.textMain)

            chips("Expires", options: GroupInviteLinks.Expiry.allCases, selection: $expiry, title: \.title)
            chips("Who can join", options: GroupInviteLinks.UseLimit.allCases, selection: $limit, title: \.title)

            Spacer(minLength: 0)

            Button {
                Task {
                    isSubmitting = true
                    defer { isSubmitting = false }
                    if await onCreate(expiry, limit) { dismiss() }
                }
            } label: {
                ButtonStateLabel("Create Link", state: isSubmitting || isCreating ? .loading : .normal)
            }
            .buttonStyle(.filled)
            .disabled(isSubmitting || isCreating)
            .accessibilityIdentifier("new-invite-link-create")
        }
        .padding(20)
    }

    private func chips<Option: Hashable>(_ heading: String, options: [Option], selection: Binding<Option>, title: KeyPath<Option, String>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(heading)
                .font(.appTextSmall)
                .foregroundStyle(Color.textSecondary)
            HStack(spacing: 8) {
                ForEach(options, id: \.self) { option in
                    let isSelected = option == selection.wrappedValue
                    Button {
                        selection.wrappedValue = option
                    } label: {
                        Text(option[keyPath: title])
                            .font(.appTextSmall)
                            .foregroundStyle(isSelected ? Color.textAction : Color.textMain)
                            .padding(.horizontal, 14)
                            .frame(height: 36)
                            .background(isSelected ? Color.action : Color.backgroundRow, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
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
        NewInviteLinkSheet(isCreating: false) { _, _ in true }
    }
}
