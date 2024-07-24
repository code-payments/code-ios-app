//
//  MessageAction.swift
//  Code
//
//  Created by Dima Bart on 2024-07-02.
//

import SwiftUI
import CodeUI

public struct MessageAction: View {
    
    public let text: String
        
    public init(text: String) {
        self.text = text
    }
    
    public var body: some View {
        HStack {
            Spacer()
            Text(text)
                .font(.appTextHeading)
                .foregroundColor(.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.backgroundMessageReceived.opacity(0.2))
                .cornerRadius(99)
            Spacer()
        }
    }
}
