//
//  TypingView.swift
//  Code
//
//  Created by Dima Bart on 2025-03-07.
//

import SwiftUI
import CodeUI

struct IndexedTypingUser: Equatable, Identifiable {
    let id: UUID
    let index: Int
    let avatarURL: URL?
}

struct TypingIndicatorView: View {
    
    var typingUsers: [IndexedTypingUser]
    
    var body: some View {
        HStack {
            AvatarStackView(
                diameter: 35,
                typingUsers: typingUsers
            )
            DotsView()
                .animation(.easeInOut(duration: 0.3), value: typingUsers)
            
            Spacer()
        }
        .padding(.horizontal, 20)
        .frame(height: 50)
        .background(Color.backgroundMain)
    }
}

struct AvatarStackView: View {
    
    let diameter: CGFloat
    let typingUsers: [IndexedTypingUser]
    
    private let max: Int = 5
    
    init(diameter: CGFloat, typingUsers: [IndexedTypingUser]) {
        self.diameter = diameter
        self.typingUsers = typingUsers
    }
    
    var body: some View {
        HStack(spacing: -(diameter * 0.5)) {
            
            let currentCount = typingUsers.count
            let users = typingUsers.count > max ? Array(typingUsers[0..<max]) : typingUsers
            
            ForEach(users) { user in
                UserGeneratedAvatar(
                    url: user.avatarURL,
                    data: user.id.data,
                    diameter: diameter
                )
                .transition(transition())
                .zIndex(Double(user.index))
            }
            
            if currentCount > max {
                moreView()
                    .transition(transition())
                    .zIndex(0)
            }
        }
        .animation(.spring(duration: 0.3), value: typingUsers)
    }
    
    func transition() -> AnyTransition {
        .asymmetric(
            insertion:
                    .move(edge: .leading)
                    .combined(with: .opacity)
                    .combined(with: .scale),
            removal:
                    .opacity
                    .combined(with: .scale(scale: 0, anchor: .leading))
        )
    }
    
    @ViewBuilder private func moreView() -> some View {
        Text("+")
            .frame(width: diameter, height: diameter, alignment: .trailing)
    }
}

struct DotsView: View {
    
    @State private var isAnimating: Bool = false
    
    var body: some View {
        HStack(spacing: 10) {
            Dot(isAnimating: $isAnimating)
                .animation(animation(delay: 0.3), value: isAnimating)
            Dot(isAnimating: $isAnimating)
                .animation(animation(delay: 0.6), value: isAnimating)
            Dot(isAnimating: $isAnimating)
                .animation(animation(delay: 0.9), value: isAnimating)
        }
        .frame(width: 40, height: 5)
        .padding(15)
        .background(Color.backgroundMessageReceived)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8)) {
                isAnimating = true
            }
        }
    }
    
    private func animation(delay: TimeInterval) -> Animation {
        .easeInOut(duration: 0.9)
        .repeatForever(autoreverses: true)
        .delay(delay)
    }
}

private struct Dot: View {
    
    @Binding var isAnimating: Bool
    
    var body: some View {
        Circle()
            .fill(.white)
            .frame(width: 8, height: 8)
            .offset(x: 0, y: isAnimating ? -1 : 0)
            .scaleEffect(isAnimating ? 1.15 : 1.0)
            .opacity(isAnimating ? 1.0 : 0.4)
    }
}
