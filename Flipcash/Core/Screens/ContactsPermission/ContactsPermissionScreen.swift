//
//  ContactsPermissionScreen.swift
//  Flipcash
//

import SwiftUI
import Contacts
import FlipcashUI

/// Contact-access gating for the Send sheet: a priming pitch while the status is
/// undetermined, and a warning to open Settings once access is denied. The parent
/// owns the ``ContactsAuthorizer`` so grants propagate via `@Observable`.
struct ContactsPermissionScreen: View {

    let authorizer: ContactsAuthorizer
    let onAllowed: () -> Void

    // MARK: - Body -

    var body: some View {
        Background(color: .backgroundMain) {
            Group {
                switch authorizer.status {
                case .denied, .restricted:
                    ContactsDeniedContent()
                case .notDetermined, .authorized, .limited:
                    ContactsPrimingContent(onContinue: requestAuthorization)
                @unknown default:
                    ContactsPrimingContent(onContinue: requestAuthorization)
                }
            }
            .padding(20)
        }
        .navigationBarBackButtonHidden(true)
        .task {
            await authorizer.refresh()
            if authorizer.status.allowsContactAccess {
                onAllowed()
            }
        }
    }

    private func requestAuthorization() {
        Task {
            let resolved = await authorizer.authorize()
            if resolved.allowsContactAccess {
                onAllowed()
            }
        }
    }
}

// MARK: - Priming -

/// Undetermined state: sells the feature and prompts for access on Continue.
private struct ContactsPrimingContent: View {

    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            Image.asset(.paperPlaneTopRight)
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("Send Money to Your Friends")
                    .font(.appTextLarge)
                    .foregroundStyle(Color.textMain)
                Text("Sync your contacts to find, invite, and pay friends")
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textSecondary)
            }
            .multilineTextAlignment(.center)
            .padding(.top, 28)

            // Bullets stay grouped just below the subtitle (rows leading-aligned
            // to each other, icons in one column). The block is centered as a
            // whole by the flanking spacers; the button is pinned to the bottom.
            VStack(alignment: .leading, spacing: 22) {
                PermissionBulletRow(icon: .checklist, text: "You decide whether to allow access")
                PermissionBulletRow(icon: .lock, text: "Synced contacts are securely stored")
                PermissionBulletRow(icon: .peopleGear, text: "Change contact access at any time")
            }
            .padding(.top, 40)

            Spacer(minLength: 0)

            Button("Continue", action: onContinue)
                .buttonStyle(.filled)
        }
    }
}

// MARK: - Denied -

/// Denied / restricted state: a warning and a centered button to open Settings.
private struct ContactsDeniedContent: View {

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            Image.asset(.exclamationTriangle)
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("Allow Contact Access")
                    .font(.appTextLarge)
                    .foregroundStyle(Color.textMain)
                Text("Turn on contact access so you can find people, send cash, and message them")
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textSecondary)
            }
            .multilineTextAlignment(.center)
            .padding(.top, 28)

            BubbleButton(text: "Settings") {
                URL.openSettings()
            }
            .padding(.top, 28)

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Bullet row -

/// One reassurance bullet: a tinted glyph and a line of copy.
private struct PermissionBulletRow: View {

    let icon: Asset
    let text: String

    var body: some View {
        HStack(spacing: 16) {
            Image.asset(icon)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .foregroundStyle(Color.textMain)
            Text(text)
                .font(.appTextMessage)
                .foregroundStyle(Color.textMain)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Previews -

#Preview("Priming") {
    NavigationStack {
        ContactsPermissionScreen(authorizer: ContactsAuthorizer(), onAllowed: {})
            .navigationTitle("Send")
            .toolbarTitleDisplayMode(.inline)
    }
    .preferredColorScheme(.dark)
}

#Preview("No Access") {
    let authorizer = ContactsAuthorizer()
    authorizer.status = .denied
    return NavigationStack {
        ContactsPermissionScreen(authorizer: authorizer, onAllowed: {})
            .navigationTitle("Send")
            .toolbarTitleDisplayMode(.inline)
    }
    .preferredColorScheme(.dark)
}
