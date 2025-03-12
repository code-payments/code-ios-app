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
    
    @Environment(TypingController.self) var typingController
    
    var typingUsers: [IndexedTypingUser] {
        typingController.typingUsers
    }
    
    var body: some View {
        HStack(alignment: .center) {
            AvatarStackView(
                diameter: 35,
                typingUsers: typingUsers
            )
            DotsView()
                .animation(.easeInOut(duration: 0.3), value: typingUsers)
            
            Spacer()
        }
        .padding(.horizontal, 20)
        .frame(height: 50, alignment: .center)
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
    @State private var animationPhase: Int = 0 // 0: off, 1-3: dot states
    @State private var timer: Timer? = nil
    
    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<3) { index in
                Dot(isAnimating: animationPhase > index)
                    .animation(.easeInOut(duration: 0.6), value: animationPhase)
            }
        }
        .frame(width: 40, height: 5)
        .padding(15)
        .background(Color.backgroundMessageReceived)
        .clipShape(cornerClip(location: .standalone(.received)))
        .onAppear {
            startAnimation()
        }
        .onDisappear {
            stopAnimation()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            startAnimation()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            stopAnimation()
        }
    }
    
    private func startAnimation() {
        stopAnimation()
        animationPhase = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true, block: updatePhase)
    }
    
    nonisolated
    private func updatePhase(timer: Timer) {
        Task { @MainActor in
            animationPhase = (animationPhase + 1) % 4 // Cycle 0-3
        }
    }
    
    private func stopAnimation() {
        timer?.invalidate()
        timer = nil
        animationPhase = 0
    }
}

private struct Dot: View {
    let isAnimating: Bool
    
    var body: some View {
        Circle()
            .fill(.white)
            .frame(width: 8, height: 8)
            .offset(x: 0, y: isAnimating ? -1 : 0)
            .scaleEffect(isAnimating ? 1.15 : 1.0)
            .opacity(isAnimating ? 1.0 : 0.4)
    }
}
