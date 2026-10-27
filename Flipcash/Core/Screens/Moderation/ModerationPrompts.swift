//
//  ModerationPrompts.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// The member and group a Silence or Remove prompt is about.
struct ModerationTarget: Identifiable, Equatable {
    let conversationID: ConversationID
    let userID: UserID
    /// What the prompt calls the member: their first name.
    let firstName: String
    let groupName: String

    var id: String { "\(conversationID)-\(userID)" }
}

/// The duration sheet for silencing one member. Picking a row applies it and dismisses, with no
/// confirm: picking again replaces the duration.
struct SilenceUserSheet: View {

    let target: ModerationTarget
    @Binding var isPresented: Bool

    @Environment(Container.self) private var container
    @Environment(SessionContainer.self) private var sessionContainer

    @State private var isWorking = false

    var body: some View {
        ChatDurationSheet(
            title: GroupModerationCopy.silenceTitle(firstName: target.firstName),
            caption: GroupModerationCopy.silenceCaption(groupName: target.groupName),
            isPresented: $isPresented
        ) {
            ForEach(SilenceDuration.allCases, id: \.self) { duration in
                ChatActionRow(
                    icon: .system(duration.systemSymbol),
                    title: duration.title,
                    accessibilityIdentifier: "silence-user-\(duration)"
                ) {
                    guard !isWorking else { return }
                    Task { await apply(duration) }
                }
            }
        }
    }

    private func apply(_ duration: SilenceDuration) async {
        isWorking = true
        defer { isWorking = false }
        let moderation = GroupModeration(
            moderation: container.flipClient,
            owner: sessionContainer.session.ownerKeyPair,
            conversationID: target.conversationID
        )
        do {
            try await moderation.silence(target.userID, duration.silence(from: .now))
            isPresented = false
        } catch {
            isPresented = false
            sessionContainer.session.dialogItem = .error(
                title: "Something Went Wrong",
                subtitle: "We were unable to silence \(target.firstName). Please try again"
            )
            ErrorReporting.captureError(error, reason: "Failed to silence user")
        }
    }
}

extension View {

    /// Presents the Silence duration sheet for `target` while it is non-nil.
    func silenceUserSheet(_ target: Binding<ModerationTarget?>) -> some View {
        sheet(item: target) { value in
            SilenceUserSheet(
                target: value,
                isPresented: Binding(
                    get: { target.wrappedValue != nil },
                    set: { if !$0 { target.wrappedValue = nil } }
                )
            )
        }
    }
}

extension ModerationTarget {

    /// The bottom-bar confirm for Remove, the same alert Block uses. Removing is a ban, so it says
    /// they can't come back until unbanned.
    @MainActor
    func removeDialog(moderation: GroupModeration, onFailure: @escaping @MainActor (Error) -> Void) -> DialogItem {
        let userID = userID
        return .alert(
            title: GroupModerationCopy.removeTitle(firstName: firstName),
            subtitle: GroupModerationCopy.removeSubtitle(groupName: groupName)
        ) {
            DialogAction.destructive("Remove") {
                Task {
                    do {
                        try await moderation.remove(userID)
                    } catch {
                        onFailure(error)
                    }
                }
            }
            DialogAction.cancel()
        }
    }
}
