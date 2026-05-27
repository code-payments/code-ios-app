//
//  ContactsPermissionScreen.swift
//  Flipcash
//

import SwiftUI
import Contacts
import FlipcashUI

/// Priming view for the system contacts authorization prompt. The parent
/// owns the ``ContactsAuthorizer`` so grants propagate via `@Observable`.
/// Pass `onSkipped: nil` to hide the secondary "Not Now" button.
struct ContactsPermissionScreen: View {

    let authorizer: ContactsAuthorizer
    let onAllowed: () -> Void
    let onSkipped: (() -> Void)?

    // MARK: - Body -

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    Spacer()
                    
                    ContactsPermissionIllustration()
                        .padding(.bottom, -60)

                    Text(title)
                        .font(.appDisplaySmall)
                        .foregroundStyle(Color.textMain)
                        .multilineTextAlignment(.center)
                    
                    Text(subtitle)
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                    
                    Spacer()
                }

                Spacer()

                Button(primaryTitle, action: primaryAction)
                    .buttonStyle(.filled)

                if let onSkipped {
                    Button("Not Now", action: onSkipped)
                        .buttonStyle(.subtle)
                }
            }
            .padding(20)
        }
        .navigationBarBackButtonHidden(true)
        .task {
            await authorizer.refresh()
            if authorizer.status == .authorized {
                onAllowed()
            }
        }
    }

    // MARK: - State-driven copy -

    private var title: String {
        switch authorizer.status {
        case .denied, .restricted, .limited:
            return "Contact Access Required"
        case .notDetermined, .authorized:
            return "Find Your Friends"
        @unknown default:
            return "Find Your Friends"
        }
    }

    private var subtitle: String {
        switch authorizer.status {
        case .denied, .restricted, .limited:
            return "Go to Settings and give Full Access"
        case .notDetermined, .authorized:
            return "Sync your contacts to find, invite,\n and pay friends"
        @unknown default:
            return "Sync your contacts to find, invite,\n and pay friends"
        }
    }

    private var primaryTitle: String {
        switch authorizer.status {
        case .denied, .restricted, .limited:
            return "Go To Settings to Give Contacts Full Access"
        case .notDetermined, .authorized:
            return "Give Access To Contacts"
        @unknown default:
            return "Give Access To Contacts"
        }
    }

    private func primaryAction() {
        switch authorizer.status {
        case .denied, .restricted, .limited:
            URL.openSettings()
        case .notDetermined:
            Task { await requestAuthorization() }
        case .authorized:
            onAllowed()
        @unknown default:
            Task { await requestAuthorization() }
        }
    }

    private func requestAuthorization() async {
        let resolved = await authorizer.authorize()
        if resolved == .authorized {
            onAllowed()
        }
    }
}

// MARK: - Illustration -

private struct ContactsPermissionIllustration: View {
    var body: some View {
        Image(.contactsPreview)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: 270)
    }
}

// MARK: - Previews -

#Preview("Priming") {
    ContactsPermissionScreen(
        authorizer: ContactsAuthorizer(),
        onAllowed: {},
        onSkipped: {}
    )
}

#Preview("No skip") {
    ContactsPermissionScreen(
        authorizer: ContactsAuthorizer(),
        onAllowed: {},
        onSkipped: nil
    )
}
