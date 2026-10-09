//
//  EditGroupScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// A group's editor, in Edit Profile's shape: the cover and photo at the top, then a card per field,
/// each opening its own screen that saves on its own.
///
/// Balance Requirements shows even on a group with none, so one can be added. Its rows open the
/// amount editor, whose save is stubbed until the contract can change a group's rules.
struct EditGroupScreen: View {

    let conversationID: ConversationID

    @Environment(ConversationController.self) private var conversationController
    @Environment(SessionContainer.self) private var sessionContainer
    @Environment(AppRouter.self) private var router

    @State private var mintNames: [PublicKey: String] = [:]

    private static let coverHeight: CGFloat = 126
    private static let avatarSize: CGFloat = 68
    private static let cardSpacing: CGFloat = 12

    private var conversation: Conversation? {
        conversationController.conversation(withID: conversationID)
    }

    private var requirements: GroupBalanceRequirements? {
        GroupBalanceRequirements(conversation?.rules)
    }

    var body: some View {
        Background(color: .backgroundMain) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    cover
                    photo
                    fieldCards
                        .padding(.top, 20)
                    balanceRequirements(requirements)
                        .padding(.top, 28)
                }
                .padding(.horizontal, ProfileHeaderMetrics.inset)
                .padding(.vertical, 24)
            }
        }
        .navigationTitle("Edit Group")
        .toolbarTitleDisplayMode(.inline)
        // An edit permission the server withdraws while this screen is open leaves the user on a
        // list of things they can no longer save. Unwinding is the honest answer, and matches the
        // gate that put the menu item there in the first place.
        .onChange(of: conversation?.canEdit ?? false) { _, canEdit in
            if !canEdit { router.popTopmost() }
        }
        .task(id: conversation?.picture?.thumbnailBlobID) {
            await sessionContainer.profileAvatars.load(.chat(conversationID), picture: conversation?.picture)
        }
        // The mint may be one the user holds nothing of, so the local store can miss and the fetch
        // is what fills it.
        .task(id: requirements?.mints) {
            let session = sessionContainer.session
            var names: [PublicKey: String] = [:]
            for mint in requirements?.mints ?? [] {
                if let stored = session.storedMintMetadata(for: mint) {
                    names[mint] = stored.name
                } else if let fetched = try? await session.fetchMintMetadata(mint: mint).name {
                    names[mint] = fetched
                }
            }
            mintNames = names
        }
    }

    // MARK: - Cover & photo -

    private var cover: some View {
        Button {
            router.push(.editGroupCover(conversationID))
        } label: {
            ProfileCoverBanner(cover: .group(conversationID, picture: conversation?.coverPicture), bannerHeight: Self.coverHeight)
                .clipShape(RoundedRectangle(cornerRadius: Metrics.boxRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("edit-group-cover")
        .overlay(alignment: .topTrailing) {
            Button("Change cover") {
                router.push(.editGroupCover(conversationID))
            }
            .buttonStyle(.plain)
            .modifier(CoverChip())
            .padding(Self.cardSpacing)
            .accessibilityIdentifier("edit-group-change-cover")
        }
    }

    /// The group picture overlapping the cover's bottom edge, with a camera badge and a caption beside it.
    private var photo: some View {
        Button {
            router.push(.editGroupPicture(conversationID))
        } label: {
            HStack(alignment: .bottom, spacing: Self.cardSpacing) {
                ContactAvatarView(
                    id: conversationID.description,
                    displayName: conversation?.title ?? "",
                    imageData: sessionContainer.profileAvatars.data(for: .chat(conversationID)),
                    blurhash: conversation?.picture?.thumbnailBlurhash,
                    size: Self.avatarSize
                )
                .overlay { Circle().strokeBorder(Color.backgroundMain, lineWidth: 5) }
                .overlay(alignment: .bottomTrailing) { cameraBadge }

                Text("Change photo")
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textSecondary)
                    .padding(.bottom, 6)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("edit-group-picture")
        .padding(.top, -Self.avatarSize / 2)
        .padding(.leading, 16)
    }

    private var cameraBadge: some View {
        Image.asset(.camera)
            .resizable()
            .scaledToFit()
            .frame(width: 16, height: 16)
            .frame(width: 28, height: 28)
            .background(Circle().fill(Color.action.opacity(0.1)))
            .background(Circle().fill(Color.backgroundMain))
            .offset(x: 6, y: 2)
    }

    // MARK: - Fields -

    private var fieldCards: some View {
        VStack(spacing: Self.cardSpacing) {
            FieldCard(title: "Group name", value: nonEmpty(conversation?.title), placeholder: "Add a name") {
                router.push(.editGroupName(conversationID))
            }
            .accessibilityIdentifier("edit-group-name")

            FieldCard(title: "Description", value: nonEmpty(conversation?.description), placeholder: "Add a description", lineLimit: 3) {
                router.push(.editGroupDescription(conversationID))
            }
            .accessibilityIdentifier("edit-group-description")
        }
    }

    // MARK: - Balance requirements -

    private func balanceRequirements(_ requirements: GroupBalanceRequirements?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Balance Requirements")
                .font(.appTextMedium)
                .foregroundStyle(Color.textMain)

            VStack(spacing: 0) {
                requirementRow("Join", requirements?.join, role: .join)
                Divider()
                    .overlay(Color.rowSeparator)
                requirementRow("Chat", requirements?.chat, role: .chat)
            }
            .background(Color.backgroundRow, in: RoundedRectangle(cornerRadius: Metrics.boxRadius, style: .continuous))

            Text("People keep their balance. These amounts determine who can join and send messages.")
                .font(.appTextSmall)
                .foregroundStyle(Color.textSecondary)
        }
        .accessibilityIdentifier("edit-group-balance-requirements")
    }

    private func requirementRow(_ title: String, _ requirement: MinimumBalanceRequirement?, role: GroupBalanceRole) -> some View {
        Button {
            router.push(.editGroupBalanceRequirement(conversationID, role: role))
        } label: {
            HStack {
                Text(title)
                    .font(.appTextMedium)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Text(requirement.map { GroupBalanceRequirements.formatted($0, mintName: $0.mints.first.flatMap { mintNames[$0] }) } ?? "None")
                    .font(.appTextMedium)
                    .foregroundStyle(Color.textMain)
                Image(systemName: "chevron.right")
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(role == .join ? "edit-group-join-requirement" : "edit-group-chat-requirement")
    }

    private func nonEmpty(_ string: String?) -> String? {
        guard let string, !string.isEmpty else { return nil }
        return string
    }
}
