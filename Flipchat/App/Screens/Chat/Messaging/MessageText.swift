//
//  MessageText.swift
//  Code
//
//  Created by Dima Bart on 2024-07-02.
//

import SwiftUI
import CodeUI
import FlipchatServices

public struct MessageText: View {
    
    public let state: Chat.Message.State
    public let name: String
    public let avatarData: Data
    public let text: String
    public let date: Date
    public let isReceived: Bool
    public let isHost: Bool
    public let location: MessageSemanticLocation
    
    private var shouldShowName: Bool {
        switch location {
        case .beginning, .standalone:
            return true
        case .middle, .end:
            return false
        }
    }
    
    private var shouldShowAvatar: Bool {
        switch location {
        case .beginning, .standalone:
            return true
        case .middle, .end:
            return false
        }
    }
    
    private var topPadding: CGFloat {
        switch location {
        case .beginning, .standalone:
            return 8
        case .middle, .end:
            return 0
        }
    }
        
    public init(state: Chat.Message.State, name: String, avatarData: Data, text: String, date: Date, isReceived: Bool, isHost: Bool, location: MessageSemanticLocation) {
        self.state = state
        self.name = name
        self.avatarData = avatarData
        self.text = text
        self.date = date
        self.isReceived = isReceived
        self.isHost = isHost
        self.location = location
    }
    
    public var body: some View {
        HStack(alignment: .bottom) {
            if isReceived {
                if shouldShowAvatar {
                    DeterministicAvatar(data: avatarData, diameter: 40)
                        .if(isHost) { $0
                            .overlay {
                                Image.asset(.crown)
                                    .position(x: 5, y: 5)
                            }
                        }
                } else {
                    VStack {
                        
                    }
                    .frame(width: 40, height: 40)
                }
            }
            
            VStack(alignment: .leading, spacing: 2) {
                if shouldShowName, isReceived {
                    Text(name)
                        .font(.appTextCaption)
                        .foregroundStyle(Color.textSecondary)
                        .padding(.leading, Metrics.chatMessageRadiusSmall)
                }
                
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
                        .padding([.horizontal], 11)
                        .padding([.vertical], 11)
                    }
                }
                .background(isReceived ? Color.backgroundMessageReceived : Color.backgroundMessageSent)
                .clipShape(
                    cornerClip(location: location)
                )
            }
        }
        .padding(.top, topPadding)
    }
}
