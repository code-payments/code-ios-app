//
//  MessageEncrypted.swift
//  Code
//
//  Created by Dima Bart on 2024-07-02.
//

import SwiftUI
import CodeUI

public struct MessageEncrypted: View {
    
    public let date: Date
    public let isReceived: Bool
    public let location: MessageSemanticLocation
        
    public init(date: Date, isReceived: Bool, location: MessageSemanticLocation) {
        self.date = date
        self.isReceived = isReceived
        self.location = location
    }
    
    public var body: some View {
        VStack(spacing: 7) {
            Image.system(.lockDashed)
                .font(.default(size: 30))
                .foregroundColor(.textMain)
                .padding(15)
            HStack {
                Spacer()
                Text(date.formattedTime())
                    .font(.appTextHeading)
                    .foregroundColor(.textSecondary)
            }
        }
        .padding([.top, .leading, .trailing], 12)
        .padding(.bottom, 8)
        .frame(width: 140)
        .background(isReceived ? Color.backgroundMessageReceived : Color.backgroundMessageSent)
        .clipShape(
            cornerClip(
                location: location
            )
        )
    }
}
