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
    var underlined: String
    var action: VoidAction
    
    init(text: String, underlined: String, action: @escaping VoidAction) {
        self.text = text
        self.underlined = underlined
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            Group {
                Text(text)
                +
                Text("\n")
                +
                Text(underlined)
                    .underline()
                
            }
            .font(.appTextSmall)
            .foregroundColor(.textSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
        }
    }
}
