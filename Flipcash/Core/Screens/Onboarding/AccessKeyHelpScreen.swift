//
//  AccessKeyHelpScreen.swift
//  Flipcash
//
//  Created by Raul Riera on 2026-02-05.
//

import SwiftUI
import FlipcashUI

struct AccessKeyHelpScreen: View {

    // MARK: - Body -

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 20) {
                    Image("PhotosApp")
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 240)

                    Text("Go to your photos app\nand search 'Flipcash'")
                        .font(.appTextSmall)
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Button("Open Photos") {
                    if let url = URL(string: "photos-redirect://") {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.filled)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .navigationTitle("Can't Find Your Access Key?")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Previews -

#Preview {
    NavigationStack {
        AccessKeyHelpScreen()
    }
}
