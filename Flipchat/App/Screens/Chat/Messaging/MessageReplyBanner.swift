//
//  MessageReplyBanner.swift
//  Code
//
//  Created by Dima Bart on 2024-12-14.
//

import SwiftUI
import CodeUI

struct MessageReplyBanner: View {
    
    let name: String
    let content: String
    let cancel: () -> Void
    
    // MARK: - Init -
    
    init(name: String, content: String, cancel: @escaping () -> Void) {
        self.name = name
        self.content = content
        self.cancel = cancel
    }
    
    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 99)
                .fill(Color.textSuccess)
                .frame(width: 4)
                .frame(maxHeight: .infinity)
                .padding(.leading, 15)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)
                    .font(.appTextMedium)
                    .foregroundStyle(Color.textMain.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Text(content)
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textMain)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            Button {
                cancel()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Color.textMain.opacity(0.5))
                    .padding(8)
                    .padding(.leading, 0)
            }
        }
        .padding(.trailing, 2)
        .padding(.vertical, 5)
        .frame(height: 55)
        .background(Color.backgroundMessageReceived)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

struct MessageReplyBannerCompact: View {
    
    static let height: CGFloat = 44
    
    let name: String
    let content: String
    
    // MARK: - Init -
    
    init(name: String, content: String) {
        self.name = name
        self.content = content
    }
    
    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(Color.textSuccess)
                .frame(width: 3)
                .frame(maxHeight: .infinity)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .lineLimit(1)
                    .font(.appTextSmall)
                    .foregroundStyle(Color.textMain.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Text(content)
                    .lineLimit(1)
                    .font(.appTextCaption)
                    .foregroundStyle(Color.textMain)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.trailing, 8)
        .background(Color.textSuccess.opacity(0.2))
        .cornerRadius(Metrics.chatMessageRadiusSmall)
        .frame(height: Self.height)
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    Background(color: .backgroundMain) {
        VStack {
            Spacer()
            MessageReplyBanner(
                name: "KinShip",
                content: "Yeah, that's what I was thinking too but I couldn't find it",
                cancel: {}
            )
            Rectangle()
                .fill(.black)
                .frame(height: 200)
                .frame(maxWidth: .infinity)
        }
    }
}
