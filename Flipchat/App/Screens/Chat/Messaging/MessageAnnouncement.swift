//
//  MessageAnnouncement.swift
//  Code
//
//  Created by Dima Bart on 2024-07-02.
//

import SwiftUI
import CodeUI

public struct MessageAnnouncement: View {
    
    public let text: String
        
    public init(text: String) {
        self.text = text
    }
    
    public var body: some View {
        HStack(alignment: .top) {
            Spacer()
            Text(text)
                .font(.appTextSmall)
                .foregroundColor(.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .multilineTextAlignment(.center)
                .background(Color.backgroundMessageReceived.opacity(0.5))
                .cornerRadius(Metrics.chatMessageRadiusLarge * 2)
            Spacer()
        }
        .padding(.top, 8)
    }
}

public struct MessageUnread: View {
    
    public let text: String
        
    public init(text: String) {
        self.text = text
    }
    
    public var body: some View {
        Text(text)
            .font(.appTextHeading)
            .foregroundColor(.ultraLightPurple)
            .padding(.vertical, 6)
            .multilineTextAlignment(.center)
            .frame(height: 30)
            .frame(maxWidth: .infinity)
            .background(Color.backgroundMessageSent)
            .padding(.bottom, 8)
            .padding(.top, 16)
    }
}
