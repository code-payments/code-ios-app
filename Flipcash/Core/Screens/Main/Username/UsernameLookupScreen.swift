//
//  UsernameLookupScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

private let logger = Logger(label: "flipcash.username-lookup")

/// Finding someone by their handle (Figma node 9491:6298). Sibling of
/// `UsernameEntryScreen`: same one field and one button, opposite direction —
/// that screen claims a handle, this one spends someone else's.
///
/// It resolves the handle itself rather than handing it to `TipFlow`, so a miss
/// lands here with the typed handle still in the field. Handing it over would
/// pop this screen first and report the miss over whatever replaced it, in copy
/// written for a followed tipcard link.
///
/// A hit shows the button's success checkmark, holds it, then pushes the chat
/// with that person (node 9443:8928), where the tip is composed — not the
/// tipcard overlay `TipFlow` raises for a scanned code. The beat is the one the
/// verification screens use (`PhoneVerificationViewModel.swift:320-329`), and so
/// is the push.
///
/// This screen then drops out from under the chat, since a chat's Back belongs
/// on the chat list. It goes while the push is still animating: the removal is a
/// whole-path rewrite, which remounts the chat, and a freshly-mounted chat
/// settles its layout a beat after it appears. Under the transition that settle
/// is hidden — the same way it is on every other push into a chat.
struct UsernameLookupScreen: View {

    @Environment(Container.self) private var container
    @Environment(SessionContainer.self) private var sessionContainer
    @Environment(Session.self) private var session
    @Environment(AppRouter.self) private var router

    private static let validator = UsernameValidator()

    @FocusState private var isFocused: Bool
    @State private var input: String = ""
    @State private var lookupTask: Task<Void, Never>?
    @State private var buttonState: ButtonState = .normal
    @State private var errorDialog: DialogItem?

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Enter Flipcash username")
                    .font(.appTextLarge)
                    .foregroundStyle(Color.textMain)
                    .padding(.top, 20)

                TextField("Username", text: $input)
                    .font(.appDisplayMedium)
                    .foregroundStyle(Color.textMain)
                    .focused($isFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .onSubmit(submit)
                    // Handles are stored lowercase, so an uppercase keystroke is
                    // a handle the server can never match. Same treatment as the
                    // claim screen, for the same reason.
                    .onChange(of: input) { _, latest in
                        let lowered = latest.lowercased()
                        if lowered != latest { input = lowered }
                    }
                    .padding(.top, 32)
                    .disabled(!buttonState.isNormal)
                    .accessibilityIdentifier("username-lookup-field")

                Text("Enter the Flipcash username of the person you want to chat with")
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textSecondary)
                    .padding(.top, 8)

                Spacer()

                Button(action: submit) {
                    ButtonStateLabel("Next", state: buttonState)
                }
                .buttonStyle(.filled)
                // Disabled for every state but `.normal`: that dims the pill
                // behind the spinner and the checkmark, and stops a second tap.
                .disabled(input.isEmpty || !buttonState.isNormal)
                .accessibilityIdentifier("username-lookup-next-button")
                .padding(.bottom, 20)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationBarTitleDisplayMode(.inline)
        .dialog(item: $errorDialog)
        .onAppear { isFocused = true }
        // Backing out abandons the lookup rather than pushing a chat onto a
        // stack the user has left. Fires on the hand-off too, once the chat
        // covers this screen, which is why the hand-off detaches itself first.
        .onDisappear { lookupTask?.cancel() }
    }

    private func submit() {
        guard buttonState.isNormal else { return }

        // Unlike the claim screen, a malformed handle isn't told which rule it
        // broke: the designer drew one dialog for this screen, and a handle that
        // cannot exist is a handle nobody has claimed.
        guard let username = Self.validator.validate(input) else {
            errorDialog = .usernameNotFound
            return
        }

        buttonState = .loading
        lookupTask = Task {
            defer {
                lookupTask = nil
                buttonState = .normal
            }

            do {
                let profile = try await container.flipClient.fetchProfile(
                    username: username,
                    owner: session.ownerKeyPair
                )
                guard !Task.isCancelled else { return }

                // An unclaimed handle answers with `Profile.empty` rather than
                // throwing (`ProfileService.swift:47-49`), so the miss is an
                // absent id here, not an error in the catch below.
                guard let userID = profile.userID else {
                    logger.info("Username not found", metadata: ["username": "\(username)"])
                    errorDialog = .usernameNotFound
                    return
                }

                logger.info("Username resolved", metadata: ["username": "\(username)"])

                try await Task.delay(milliseconds: 500)
                buttonState = .success
                try await Task.delay(milliseconds: 500)

                // Your own handle has no chat to open — one tipcard is what
                // scanning your own code already shows.
                guard userID != session.userID else {
                    sessionContainer.tipFlow.begin(userID: userID)
                    return
                }

                // The chat is created by the first tip, so until then the
                // screen's only source for the counterpart's name, picture, and
                // handle is the profile this lookup just fetched.
                session.cacheUserProfile(profile, for: userID)

                // Detached before the push: covering this screen fires the
                // `onDisappear` cancel, and what follows the push is cleanup
                // that has to run anyway.
                lookupTask = nil

                let chat = AppRouter.Destination.tipConversationForUser(userID)
                router.push(chat)

                // Well inside the push transition, so the remounted chat settles
                // behind the animation rather than in front of the user. Late
                // enough that SwiftUI has committed the push as its own update:
                // rewriting in the same tick coalesces the two into a leaf swap,
                // which it draws as a cut.
                try await Task.delay(milliseconds: 150)

                // Unless they went back while it landed: the lookup left with
                // them, and rewriting the path would drag the chat back.
                guard router[.tips].count == 2 else { return }

                // Unanimated, because nothing is arriving — only the entry
                // underneath is leaving. Animated, SwiftUI stages the remount as
                // a second push: the same chat sliding in over the one already
                // on screen.
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    router.setPath([chat], on: .tips)
                }

            } catch {
                guard !Task.isCancelled else { return }
                logger.error("Failed to look up username", metadata: ["error": "\(error)"])

                // Captured unconditionally: `ErrorFetchProfile.reportingLevel`
                // already files `.notFound` as `.info` and a transport failure as
                // `.suppressed`, so gating here would duplicate that judgement.
                ErrorReporting.captureError(error, reason: "Failed to look up username")

                errorDialog = .usernameLookup(for: error)
            }
        }
    }
}
