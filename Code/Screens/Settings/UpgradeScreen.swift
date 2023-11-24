//
//  UpgradeScreen.swift
//  Code
//
//  Created by Dima Bart on 2021-11-26.
//

import SwiftUI
import CodeServices
import CodeUI

struct UpgradeScreen: View {
    
    // MARK: - Init -
    
    init() {}
    
    // MARK: - Body -
    
    var body: some View {
        Background(color: .backgroundMain) {
            VStack(spacing: 0) {
                VStack(alignment: .center, spacing: 20) {
                    Spacer()
                    Text(Localized.Title.updateRequired)
                        .font(.appTextLarge)
                        .foregroundColor(.textMain)
                    Text(Localized.Subtitle.updateRequiredDescription)
                        .font(.appTextSmall)
                        .foregroundColor(.textSecondary)
                        .padding([.leading, .trailing], 20)
                    Spacer()
                }
                
                Spacer()
                CodeButton(style: .filled, title: Localized.Action.update) {
                    URL.downloadCode.openWithApplication()
                }
            }
            .multilineTextAlignment(.center)
            .padding(20)
        }
        .onAppear {
            Analytics.open(screen: .forceUpgrade)
            ErrorReporting.breadcrumb(.forceUpgradeScreen)
        }
    }
}

// MARK: - Previews -

struct UpgradeScreen_Previews: PreviewProvider {
    static var previews: some View {
        UpgradeScreen()
        .preferredColorScheme(.dark)
    }
}
