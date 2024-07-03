//
//  RevealIdentityBanner.swift
//  Code
//
//  Created by Dima Bart on 2024-07-02.
//

import SwiftUI
import CodeUI

struct RevealIdentityBanner: View {
    
    var action: VoidAction
    
    init(action: @escaping VoidAction) {
        self.action = action
    }
    
    var body: some View {
        HStack {
            Text("Your messages are showing up anonymously.\nWould you like to reveal your identity?")
                .font(.appTextSmall)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.leading)
            
            Spacer()
            
            Button {
                action()
            } label: {
                TextBubble(
                    style: .filled,
                    text: "Reveal",
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
