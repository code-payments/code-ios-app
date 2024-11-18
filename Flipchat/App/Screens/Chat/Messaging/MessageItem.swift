//
//  MessageItem.swift
//  Code
//
//  Created by Dima Bart on 2024-07-02.
//

import SwiftUI
import CodeUI

public struct MessageItem: View {
    
    public let text: String
    public let subtitle: String
    public let isReceived: Bool
    public let location: MessageSemanticLocation
        
    public init(text: String, subtitle: String, isReceived: Bool, location: MessageSemanticLocation) {
        self.text = text
        self.subtitle = subtitle
        self.isReceived = isReceived
        self.location = location
    }
    
    public var body: some View {
        VStack(spacing: 7) {
            Text(text)
                .font(.appTextMedium)
                .foregroundColor(.textMain)
            HStack {
                Spacer()
                Text(subtitle)
                    .font(.appTextSmall)
                    .foregroundColor(.textSecondary)
            }
        }
        .padding([.top, .leading, .trailing], 20)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity)
        .background(isReceived ? Color.backgroundMessageReceived : Color.backgroundMessageSent)
        .clipShape(
            cornerClip(
                location: location
            )
        )
    }
}
