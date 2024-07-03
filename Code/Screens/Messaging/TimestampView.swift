//
//  TimestampView.swift
//  Code
//
//  Created by Dima Bart on 2024-07-02.
//

import SwiftUI
import CodeUI
import CodeServices

struct TimestampView: View {
    
    let state: Chat.Message.State
    let date: Date
    let isReceived: Bool
    
    init(state: Chat.Message.State, date: Date, isReceived: Bool) {
        self.state = state
        self.date = date
        self.isReceived = isReceived
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Text(date.formattedTime())
                .font(.appTextHeading)
                .foregroundColor(.textSecondary)
            if !isReceived {
                Image.asset(state.asset)
            }
        }
    }
}

private extension Chat.Message.State {
    var asset: Asset {
        switch self {
        case .sent:
            return .statusSent
        case .delivered:
            return .statusDelivered
        case .read:
            return .statusRead
        }
    }
}
