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
    
    // MARK: - Init -
    
    init() {
        
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
                
                CodeButton(
                    style: .filled,
                    title: Localized.Action.connectToX
                ) {
                    
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
    RequestTipScreen()
}
