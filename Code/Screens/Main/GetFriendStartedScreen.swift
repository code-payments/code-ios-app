//
//  GetFriendStartedScreen.swift
//  Code
//
//  Created by Dima Bart on 2023-06-02.
//

import SwiftUI
import CodeUI
import CodeServices

struct GetFriendStartedScreen: View {
    
    // MARK: - Init -
    
    public init() {}
    
    // MARK: - Init -
    
    var body: some View {
        Background(color: .backgroundMain) {
            VStack(alignment: .leading, spacing: 40) {
                Spacer()
                
                VStack(alignment: .leading, spacing: 20) {
                    Text(Localized.Title.getFriendStartedOnCode)
                        .font(.appDisplayMedium)
                        .frame(maxWidth: 330, alignment: .leading)
                    
                    Text(Localized.Subtitle.getFriendStartedOnCode)
                        .font(.appTextMedium)
                }
                
                Spacer() // Offset from center, top bias
                Spacer()
                
                CodeButton(style: .filled, title: Localized.Action.shareDownloadLink) {
                    ShareSheet.present(url: .downloadCode)
                }
            }
            .frame(maxHeight: .infinity)
            .padding(20)
            .foregroundColor(.textMain)
        }
        .onAppear {
            Analytics.open(screen: .getFriendStarted)
            ErrorReporting.breadcrumb(.getFriendStartedScreen)
        }
    }
}

struct GetFriendStartedScreen_Previews: PreviewProvider {
    static var previews: some View {
        GetFriendStartedScreen()
    }
}
