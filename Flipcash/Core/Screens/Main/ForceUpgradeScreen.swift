//
//  ForceUpgradeScreen.swift
//  Flipcash
//
//  Created by Claude Code.
//

import SwiftUI
import FlipcashUI
import FlipcashCore

struct ForceUpgradeScreen: View {

    // MARK: - Body -

    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 0) {
                VStack(alignment: .center, spacing: 15) {
                    Spacer()
                    
                    VStack(alignment: .center, spacing: 25) {
                        Image.asset(.downloadCircle)
                            .renderingMode(.template)
                            .foregroundStyle(Color.textMain)
                        
                        Text("Update Required")
                            .font(.appTextLarge)
                            .foregroundColor(.textMain)
                    }

                    Text("The latest features of Flipcash require you to update to the latest version")
                        .font(.appTextSmall)
                        .foregroundColor(.textSecondary)
                        .padding([.leading, .trailing], 20)

                    Spacer()
                }

                Spacer()

                CodeButton(style: .filled, title: "Update Now") {
                    URL.appStoreApplicationHome.openWithApplication()
                }
            }
            .multilineTextAlignment(.center)
            .padding(20)
        }
    }
}

// MARK: - Previews -

#Preview {
    ForceUpgradeScreen()
}

struct ForceUpgradeScreen_Previews: PreviewProvider {
    static var previews: some View {
        ForceUpgradeScreen()
            .preferredColorScheme(.dark)
    }
}
