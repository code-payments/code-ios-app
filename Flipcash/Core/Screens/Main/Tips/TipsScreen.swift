//
//  TipsScreen.swift
//  Flipcash
//

import SwiftUI
import FlipcashCore
import FlipcashUI

/// The Tips sheet's root: the tipcard once a profile exists, the invitation to
/// create one until then.
struct TipsScreen: View {

    @Environment(SessionContainer.self) private var sessionContainer

    var body: some View {
        if sessionContainer.session.profile?.isTippable == true {
            TipcardScreen()
        } else {
            TipsIntroScreen()
        }
    }
}

// MARK: - TipsIntroScreen -

private struct TipsIntroScreen: View {

    @Environment(AppRouter.self) private var router

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 0) {
                Spacer()

                // The tab-bar asset carries a heavier stroke tuned for 40pt;
                // at this size it needs the lighter one.
                Image(.Icons.tipsLarge)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                    .foregroundStyle(Color.textMain)

                Text("Receive Tips From Everyone")
                    .font(.appTextLarge)
                    .foregroundStyle(Color.textMain)
                    .multilineTextAlignment(.center)
                    .padding(.top, 32)

                Text("Add your name and a picture to receive tips")
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)

                Spacer()

                Button("Start Receiving Tips") {
                    router.push(.profileName)
                }
                .buttonStyle(.filled)
                .accessibilityIdentifier("start-receiving-tips-button")
                .padding(.bottom, 20)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Tips")
        .toolbarTitleDisplayMode(.inline)
    }
}
