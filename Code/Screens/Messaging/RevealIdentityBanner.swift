//
//  RevealIdentityBanner.swift
//  Code
//
//  Created by Dima Bart on 2024-07-02.
//

import SwiftUI
import CodeUI

struct RevealIdentityBanner: View {
    
    var text: String
    var action: VoidAction
    
    init(text: String, action: @escaping VoidAction) {
        self.text = text
        self.action = action
    }
    
    var body: some View {
        HStack {
            Text(text)
                .font(.appTextSmall)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.leading)
            
            Spacer()
            
            Button {
                action()
            } label: {
                TextBubble(
                    style: .filled,
                    text: Localized.Action.reveal,
                    paddingVertical: 2,
                    paddingHorizontal: 6
                )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
    }
}
