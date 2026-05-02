//
//  ForceLogoutScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct ForceLogoutScreen: View {

    @Environment(SessionAuthenticator.self) private var sessionAuthenticator

    // MARK: - Body -

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 0) {
                VStack(alignment: .center, spacing: 15) {
                    Spacer()

                    Text("Access Key No Longer Usable in Flipcash")
                        .font(.appTextLarge)
                        .foregroundStyle(.textMain)

                    Text("Your Access Key has initiated an unlock. As a result, you will no longer be able to use this Access Key in Flipcash.")
                        .font(.appTextSmall)
                        .foregroundStyle(.textSecondary)
                        .padding([.leading, .trailing], 20)

                    Spacer()
                }

                Spacer()

                Button("Log Out") {
                    sessionAuthenticator.logout()
                }
                .buttonStyle(.filled)
            }
            .multilineTextAlignment(.center)
            .padding(20)
        }
    }
}

// MARK: - Previews -

#Preview {
    ForceLogoutScreen()
        .environment(SessionAuthenticator.mock)
}

struct ForceLogoutScreen_Previews: PreviewProvider {
    static var previews: some View {
        ForceLogoutScreen()
            .environment(SessionAuthenticator.mock)
            .preferredColorScheme(.dark)
    }
}
