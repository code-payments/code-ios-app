//
//  PillButton.swift
//  Code
//
//  Created by Dima Bart on 2025-01-14.
//

import SwiftUI

struct PillButton: View {
    
    private let text: String
    private let action: () -> Void
    
    init(text: String, action: @escaping () -> Void) {
        self.text = text
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.appTextSmall)
                .foregroundStyle(Color.backgroundMain)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.textMain)
                .cornerRadius(99)
        }
    }
}
