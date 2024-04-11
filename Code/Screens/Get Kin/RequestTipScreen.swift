//
//  RequestTipScreen.swift
//  Code
//
//  Created by Dima Bart on 2024-04-05.
//

import SwiftUI
import CodeUI
import CodeServices

struct RequestTipScreen: View {
    
    private let session: Session
    
    @State private var nonce = UUID()
    
    // MARK: - Init -
    
    init(session: Session) {
        self.session = session
    }
    
    // MARK: - Body -
    
    var body: some View {
        Background(color: .backgroundMain) {
            VStack(alignment: .leading, spacing: 40) {
                VStack(alignment: .leading, spacing: 20) {
                    Text(Localized.Title.requestTip)
                        .font(.appDisplayMedium)
                    
                    Text(Localized.Subtitle.tipCardForX)
                        .font(.appTextMedium)
                }
                
                Spacer()
                
                HStack(alignment: .top, spacing: 15) {
                    PlaceholderAvatar(diameter: 25)
                    Text(session.generateTwitterAuthMessage(nonce: nonce))
                        .font(.appTextSmall)
                        .foregroundColor(.textMain)
                }
                .padding(20)
                .background(Color.bannerInfo)
                .cornerRadius(4)
                
                Spacer()
                Spacer()
                
                CodeButton(
                    style: .filled,
                    title: Localized.Action.connectToX
                ) {
                    session.generateTwitterAuthURL(nonce: nonce).openWithApplication()
                }
            }
            .foregroundColor(.textMain)
            .frame(maxHeight: .infinity)
            .padding(.top, 20)
            .padding(.bottom, 20)
            .padding(.horizontal, 20)
        }
        .navigationBarTitle(Text(""), displayMode: .inline)
    }
}

#Preview {
    RequestTipScreen(session: .mock)
}
