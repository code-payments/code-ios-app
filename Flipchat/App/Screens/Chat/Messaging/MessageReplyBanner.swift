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
    let verificationType: VerificationType
    let content: String
    let cancel: () -> Void
    
    // MARK: - Init -
    
    init(name: String, verificationType: VerificationType, content: String, cancel: @escaping () -> Void) {
        self.name = name
        self.verificationType = verificationType
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
                MemberNameLabel(
                    size: .medium,
                    showLogo: false,
                    name: name,
                    verificationType: verificationType
                )
                
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
    
    static let height: CGFloat = 50
    
    let name: String
    let content: String
    let expand: Bool
    let deleted: Bool
    let action: () -> Void
    
    // MARK: - Init -
    
    init(name: String, content: String, expand: Bool = false, deleted: Bool = false, action: @escaping () -> Void) {
        self.name = name
        self.content = content
        self.expand = expand
        self.deleted = deleted
        self.action = action
    }
    
    var body: some View {
        Button {
            action()
        } label: {
            HStack(spacing: 10) {
                Rectangle()
                    .fill(Color.textSuccess)
                    .frame(width: 3)
                    .frame(maxHeight: .infinity)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .lineLimit(1)
                        .font(.appTextSmall)
                        .foregroundStyle(Color.textMain.opacity(0.8))
                        .if(expand) { $0
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    
                    Text(content)
                        .lineLimit(1)
                        .font(.appTextCaption)
                        .foregroundStyle(Color.textMain.opacity(deleted ? 0.6 : 1.0))
                        .if(expand) { $0
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                }
            }
            .padding(.trailing, 10)
            .background(Color.textSuccess.opacity(0.2))
            .cornerRadius(Metrics.chatMessageRadiusSmall)
            .frame(height: Self.height)
        }
    }
}

#Preview {
    Background(color: .backgroundMain) {
        VStack {
            Spacer()
            MessageReplyBannerCompact(
                name: "KinShip",
                content: "Yeah, that's what I was thinking too but I couldn't find it",
                expand: true,
                action: {}
            )
            Rectangle()
                .fill(.black)
                .frame(height: 200)
                .frame(maxWidth: .infinity)
        }
    }
}
