//
//  MemberSheet.swift
//  Flipcash
//
//  Copyright © 2026 Code Inc. All rights reserved.
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// The member a sheet is open for, and what the entry point already knows about them.
struct MemberSheetTarget: Identifiable, Equatable {
    let conversationID: ConversationID
    let userID: UserID
    /// The name and picture the tapped portrait drew, shown until the profile loads.
    var portrait: GroupPortrait?

    var id: String { "\(conversationID)-\(userID)" }
}

/// Runs the host's group actions on one member for the Members swipe and the member sheet, keeping
/// the roster and the restricted state in step with what succeeded.
@MainActor
struct MemberModerator {

    let conversationID: ConversationID
    let sessionContainer: SessionContainer
    let toasts: ToastController
    /// How long a toast waits, so one raised as a sheet closes isn't dropped under it.
    var toastDelay: Duration = .zero

    var moderation: GroupModeration {
        GroupModeration(
            moderation: sessionContainer.flipClient,
            owner: sessionContainer.session.ownerKeyPair,
            conversationID: conversationID,
            announce: { [toasts, toastDelay] message in
                Task {
                    try? await Task.sleep(for: toastDelay)
                    toasts.show(.init(message, systemImage: "speaker.wave.2", duration: .seconds(3)))
                }
            },
            didRemove: { [rosters = sessionContainer.groupRosters, conversationID] in
                rosters.remove($0, from: conversationID)
            },
            didChangeSilence: { [restrictions = sessionContainer.groupRestrictions, conversationID] in
                restrictions.record($1, for: $0, in: conversationID)
            }
        )
    }

    /// Lifts `userID`'s restriction, with the Restricted list's toast on success and its error on failure.
    func lift(_ userID: UserID, firstName: String) async {
        do {
            try await moderation.unsilence(userID, firstName: firstName)
        } catch {
            sessionContainer.session.dialogItem = .error(
                title: "Something Went Wrong",
                subtitle: "We were unable to lift the restriction on \(firstName). Please try again"
            )
            ErrorReporting.captureError(error, reason: "Failed to lift the restriction on user")
        }
    }

    /// Shows the shipped Remove confirm for `target`.
    func confirmRemove(_ target: ModerationTarget) {
        sessionContainer.session.dialogItem = target.removeDialog(moderation: moderation) { [session = sessionContainer.session] error in
            session.dialogItem = .error(
                title: "Something Went Wrong",
                subtitle: "We were unable to remove \(target.firstName). Please try again"
            )
            ErrorReporting.captureError(error, reason: "Failed to remove user")
        }
    }
}

/// What the member sheet hands back to its presenter, run once the sheet has gone.
enum MemberSheetFollowUp: Equatable {
    case viewProfile
    case report
    case restrict(ModerationTarget)
    case remove(ModerationTarget)
}

/// A member's picture, name and handle with View Profile, plus the group's actions on them for a
/// host or Report for everyone else (nodes 13252:1341, 13252:1427, 13252:1513).
struct MemberSheet: View {

    let target: MemberSheetTarget
    @Binding var isPresented: Bool
    /// Told the action picked, just before the sheet closes.
    let followUp: (MemberSheetFollowUp) -> Void

    @Environment(SessionContainer.self) private var sessionContainer
    @Environment(ConversationController.self) private var conversationController
    @Environment(ToastController.self) private var toasts
    @Environment(AppRouter.self) private var router

    @State private var profile: UserProfileViewModel?
    @State private var isLifting = false

    private var conversation: Conversation? {
        conversationController.conversation(withID: target.conversationID)
    }

    private var canModerate: Bool {
        guard let state = conversation?.viewerState else { return false }
        return state.canSilence || state.canBan
    }

    private var displayName: String {
        profile?.name ?? target.portrait?.name ?? profile?.displayName ?? ConversationController.fallbackCounterpartName
    }

    private var groupName: String {
        conversation?.title ?? "this group"
    }

    private func options(at date: Date) -> MemberModerationOptions {
        let state = conversation?.viewerState
        return MemberModerationOptions.resolve(
            canSilence: state?.canSilence ?? false,
            canBan: state?.canBan ?? false,
            isCreator: conversation?.creator == target.userID,
            isSelf: target.userID == sessionContainer.session.userID,
            isRestricted: silence(at: date) != nil
        )
    }

    private func silence(at date: Date) -> ConversationSilenceState? {
        sessionContainer.groupRestrictions.silence(of: target.userID, in: target.conversationID, at: date)
    }

    private var moderationTarget: ModerationTarget {
        ModerationTarget(
            conversationID: target.conversationID,
            userID: target.userID,
            firstName: GroupModerationCopy.firstName(of: displayName),
            groupName: groupName
        )
    }

    var body: some View {
        PartialSheet(background: .backgroundMain) {
            TimelineView(.everyMinute) { context in
                let options = options(at: context.date)
                VStack(alignment: .leading, spacing: 20) {
                    header

                    if options.showsRestriction, let silence = silence(at: context.date) {
                        Text(GroupModerationCopy.restrictedStatus(silence, now: context.date))
                            .font(.appTextSmall)
                            .foregroundStyle(Color.warning)
                            .accessibilityIdentifier("member-sheet-restriction")
                    }

                    CodeButton(style: .filled, title: "View Profile") {
                        close(with: .viewProfile)
                    }
                    .accessibilityIdentifier("member-sheet-view-profile")

                    if options.hasGroupActions {
                        groupSection(options)
                    } else if options.showsReport {
                        ChatActionRow(
                            // The outline, as the profile's ⋯ menu draws Report.
                            icon: Image(systemName: "exclamationmark.bubble"),
                            title: "Report",
                            accessibilityIdentifier: "member-sheet-report"
                        ) {
                            close(with: .report)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, bottomPadding)
        }
        .task {
            let seed = target.portrait.map {
                CounterpartSeed(name: $0.name, username: nil, imageData: nil, blurhash: $0.picture?.thumbnailBlurhash)
            } ?? conversationController.counterpartSeed(forUserID: target.userID)
            let model = UserProfileViewModel(
                userID: target.userID,
                flipClient: sessionContainer.flipClient,
                owner: sessionContainer.session.ownerKeyPair,
                blocklistController: sessionContainer.blocklistController,
                router: router,
                blockReturnsToOpener: UserProfileOrigin.groupMember(target.conversationID).blockReturnsToOpener,
                arrivesFetched: false,
                session: sessionContainer.session,
                profileAvatars: sessionContainer.profileAvatars,
                seed: seed
            )
            profile = model
            await model.loadProfile()
        }
        .task(id: target.conversationID) {
            // A host can reach this sheet from a cold launch with nothing read yet.
            guard canModerate else { return }
            await sessionContainer.groupRestrictions.refresh(target.conversationID)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            ContactAvatarView(
                id: target.userID.uuidString,
                displayName: displayName,
                imageData: profile?.imageData ?? sessionContainer.profileAvatars.data(for: target.userID),
                blurhash: profile?.blurhash ?? target.portrait?.picture?.thumbnailBlurhash,
                size: 64
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(.appTextLarge)
                    .foregroundStyle(Color.textMain)
                if let handle = profile?.username?.handle {
                    Text(handle)
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .lineLimit(1)
            .padding(.top, 6)
            Spacer(minLength: 8)
            CloseButton(style: .glass, binding: $isPresented)
        }
    }

    private func groupSection(_ options: MemberModerationOptions) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("In \(groupName)")
                .font(.appTextHeading)
                .foregroundStyle(Color.textSecondary)
                .textCase(.uppercase)
                .lineLimit(1)

            switch options.silence {
            case .restrict:
                ChatActionRow(
                    icon: .system(.clock),
                    title: "Restrict",
                    tint: .textError,
                    accessibilityIdentifier: "member-sheet-restrict"
                ) {
                    close(with: .restrict(moderationTarget))
                }
            case .lift:
                ChatActionRow(
                    icon: Image(systemName: "lock.open"),
                    title: "Lift Restriction",
                    accessibilityIdentifier: "member-sheet-lift"
                ) {
                    lift()
                }
                .disabled(isLifting)
            case nil:
                EmptyView()
            }

            if options.canRemove {
                ChatActionRow(
                    icon: .system(.personBadgeMinus),
                    title: "Remove from Group",
                    tint: .textError,
                    accessibilityIdentifier: "member-sheet-remove"
                ) {
                    close(with: .remove(moderationTarget))
                }
            }
        }
    }

    private func close(with action: MemberSheetFollowUp) {
        followUp(action)
        isPresented = false
    }

    private func lift() {
        guard !isLifting else { return }
        isLifting = true
        let moderator = MemberModerator(
            conversationID: target.conversationID,
            sessionContainer: sessionContainer,
            toasts: toasts,
            toastDelay: .milliseconds(600)
        )
        let firstName = moderationTarget.firstName
        Task {
            await moderator.lift(target.userID, firstName: firstName)
            isLifting = false
            isPresented = false
        }
    }

    /// The design's 16 under the last row, less whatever the sheet already holds back for the home
    /// indicator. Matches ``ChatDurationSheet``.
    private var bottomPadding: CGFloat {
        let reserved = UIApplication.shared.currentKeyWindow?.safeAreaInsets.bottom ?? 0
        return max(0, 16 - reserved)
    }
}

extension View {

    /// Presents the member sheet for `target` while it is non-nil, and runs what the sheet picked
    /// once it has gone: the profile push, the Restrict durations, the Remove confirm, or Report.
    func memberSheet(_ target: Binding<MemberSheetTarget?>) -> some View {
        modifier(MemberSheetPresenter(target: target))
    }
}

private struct MemberSheetPresenter: ViewModifier {

    @Binding var target: MemberSheetTarget?

    @Environment(SessionContainer.self) private var sessionContainer
    @Environment(ToastController.self) private var toasts
    @Environment(AppRouter.self) private var router

    /// The sheet's pick, held until it has finished closing so the next screen doesn't land under it.
    @State private var pending: (target: MemberSheetTarget, action: MemberSheetFollowUp)?
    @State private var silenceTarget: ModerationTarget?
    @State private var report: ReportRequest?

    private struct ReportRequest: Identifiable {
        let userID: UserID
        var id: UserID { userID }
    }

    func body(content: Content) -> some View {
        content
            .sheet(item: $target, onDismiss: runPending) { value in
                MemberSheet(
                    target: value,
                    isPresented: Binding(
                        get: { target != nil },
                        set: { if !$0 { target = nil } }
                    ),
                    followUp: { pending = (value, $0) }
                )
            }
            .silenceUserSheet($silenceTarget)
            .fullScreenCover(item: $report) { request in
                NavigationStack {
                    ReportFlowScreen(target: .user(request.userID))
                }
            }
    }

    private func runPending() {
        guard let (sheetTarget, action) = pending else { return }
        pending = nil
        switch action {
        case .viewProfile:
            router.push(.userProfile(sheetTarget.userID, origin: .groupMember(sheetTarget.conversationID)))
        case .report:
            report = ReportRequest(userID: sheetTarget.userID)
        case .restrict(let moderationTarget):
            silenceTarget = moderationTarget
        case .remove(let moderationTarget):
            MemberModerator(conversationID: sheetTarget.conversationID, sessionContainer: sessionContainer, toasts: toasts)
                .confirmRemove(moderationTarget)
        }
    }
}
