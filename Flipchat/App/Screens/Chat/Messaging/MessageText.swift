//
//  MessageText.swift
//  Code
//
//  Created by Dima Bart on 2024-07-02.
//

import SwiftUI
import CodeUI
import CodeServices
import FlipchatServices

public struct MessageText: View {
    
    public let state: Chat.Message.State
    public let text: String
    public let date: Date
    public let isReceived: Bool
    public let location: MessageSemanticLocation
        
    public init(state: Chat.Message.State, text: String, date: Date, isReceived: Bool, location: MessageSemanticLocation) {
        self.state = state
        self.text = text
        self.date = date
        self.isReceived = isReceived
        self.location = location
    }
    
    public var body: some View {
        Group {
            if text.count < 10 {
                HStack(alignment: .bottom) {
                    Text(text)
                        .font(.appTextMessage)
                        .foregroundColor(.textMain)
                        .multilineTextAlignment(.leading)
                    
                    TimestampView(state: state, date: date, isReceived: isReceived)
                }
                .padding([.horizontal], 10)
                .padding([.vertical], 8)
                
            } else {
                VStack(alignment: .trailing, spacing: 5) {
                    Text(text)
                        .font(.appTextMessage)
                        .foregroundColor(.textMain)
                        .multilineTextAlignment(.leading)
                    
                    TimestampView(state: state, date: date, isReceived: isReceived)
                }
                .padding([.horizontal], 10)
                .padding([.vertical], 8)
            }
        }
        .background(isReceived ? Color.backgroundMessageReceived : Color.backgroundMessageSent)
        .clipShape(
            cornerClip(
                isReceived: isReceived,
                location: location
            )
        )
    }
}
