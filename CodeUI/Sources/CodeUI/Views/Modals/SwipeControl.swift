//
//  SwipeControl.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI

public struct SwipeControl: View {
    
    @GestureState private var drag: Drag = .ready
    
    @State private var position: CGPoint = .zero
    
    @State private var state: KnobState = .normal
    
    @State private var isPropped: Bool = false
    
    @State private var timer: Timer? = nil
    
    private let style: Style
    private let text: String
    private let action: ThrowingAction
    private let completion: ThrowingAction?
    
    // MARK: - Init -
    
    public init(style: Style, text: String, action: @escaping ThrowingAction, completion: ThrowingAction? = nil) {
        self.style = style
        self.text = text
        self.action = action
        self.completion = completion
    }
    
    // MARK: - Body -
    
    public var body: some View {
        ZStack {
            Text(text)
                .lineLimit(1)
                .font(.appTextMedium)
                .foregroundColor(.textMain)
                .padding(.horizontal, 60)
            
            GeometryReader { geometry in
                HStack {
                    RoundedRectangle(cornerRadius: 5)
                        .frame(width: Self.knobSize.width, height: Self.knobSize.height)
                        .foregroundColor(.textMain)
                        .overlay {
                            Image.system(.arrowRight)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 18, height: 18, alignment: .center)
                                .foregroundColor(.black)
                        }
                        .background {
                            RoundedRectangle(cornerRadius: 5)
                                .frame(width: geometry.size.width + Self.knobSize.width * 2, height: Self.knobSize.height)
                                .foregroundColor(style.railColor)
                                .offset(x: Self.knobSize.width * 0.5 - geometry.size.width * 0.5 - Self.knobSize.width)
                        }
                        .offset(
                            x: position.x + drag.offset.x + (drag == .ready && isPropped ? 20 : 0),
                            y: position.y + drag.offset.y
                        )
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .updating($drag) { value, drag, transaction in
                                    transaction.disablesAnimations = true
                                    
                                    let maxX   = geometry.size.width - Self.knobSize.width
                                    let offset = max(min(value.translation.width, maxX), 0)
                                    
                                    switch drag {
                                    case .ready:
                                        drag = .started(CGPoint(x: offset, y: 0))
                                    case .started:
                                        drag = .dragging(CGPoint(x: offset, y: 0))
                                    case .dragging:
                                        drag = .dragging(CGPoint(x: offset, y: 0))
                                    }
                                }
                                .onEnded { value in
                                    let maxX   = geometry.size.width - Self.knobSize.width
                                    let offset = max(min(value.translation.width, maxX), 0)
                                    
                                    let velocity = CGPoint(
                                        x: value.predictedEndLocation.x - value.location.x,
                                        y: value.predictedEndLocation.y - value.location.y
                                    )
                                    
                                    let percentComplete = offset / maxX
                                    if percentComplete > 0.7 || (percentComplete > 0.5 && velocity.x > 200.0) {
                                        
                                        state = .loading
                                        position.x = maxX + Self.knobSize.width * 2
                                        
                                        Task {
                                            defer {
                                                Task {
                                                    try await Task.delay(seconds: 2)
                                                    state = .normal
                                                    position.x = 0
                                                }
                                            }
                                            do {
                                                try await action()
                                                state = .success
                                                
                                                if let completion {
                                                    try await completion()
                                                }
                                                
                                            } catch {
                                                state = .normal
                                                position.x = 0
                                            }
                                        }
                                    }
                                }
                        )
                        .disabled(state != .normal)
                        .animation(.springFastestDamped, value: drag)
                        .animation(.springFastestDamped, value: position)
                        .animation(.springFastestDamped, value: isPropped)
                        .onChange(of: drag) { newValue in
                            switch newValue {
                            case .ready:
                                createTimer()
                                
                            case .started:
                                deleteTimer()
                                
                            case .dragging:
                                break
                            }
                        }
                    
                    Spacer()
                }
                .frame(height: Self.height)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 4)
        .frame(height: Self.height)
        .background(style.railColor)
        .cornerRadius(8)
        .overlay {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.textSecondary.opacity(0.3), lineWidth: 1.0 / UIScreen.main.scale)
                VStack {
                    switch state {
                    case .normal:
                        EmptyView()
                        
                    case .loading:
                        LoadingView(color: .gray, style: .medium)
                        
                    case .success:
                        Image.asset(.checkmarkLarge)
                            .renderingMode(.template)
                            .offset(x: 1, y: 1)
                            .foregroundColor(.textSuccess)
                    }
                }
                .animation(nil, value: state)
            }
        }
        .onAppear {
            Task {
                try await Task.delay(seconds: 3)
                createTimer()
                timerTick()
            }
        }
    }
    
    // MARK: - Timer -
    
    private func createTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { _ in
            timerTick()
        }
    }
    
    private func deleteTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    private func timerTick() {
        isPropped = true
        Task {
            try await Task.delay(milliseconds: 150)
            isPropped = false
        }
    }
}

// MARK: - Style -

public enum Style {
    
    case blue
    case black
    case purple
    
    private static let railColorBlue: Color   = Color(r: 17,  g: 20,  b: 42)
    private static let railColorBlack: Color  = Color(r: 32,  g: 29,  b: 29)
    private static let railColorPurple: Color = Color(r: 36,  g: 26,  b: 75)
    
    var railColor: Color {
        switch self {
        case .blue:
            return Self.railColorBlue
        case .black:
            return Self.railColorBlack
        case .purple:
            return Self.railColorPurple
        }
    }
}

private enum KnobState {
    case normal
    case loading
    case success
}

private enum Drag: Equatable {
    
    case ready
    case started(CGPoint)
    case dragging(CGPoint)
    
    var offset: CGPoint {
        switch self {
        case .ready:
            return .zero
        case .started(let p):
            return p
        case .dragging(let p):
            return p
        }
    }
}

extension SwipeControl {
    
    private static let knobSize: CGSize = CGSize(width: 60, height: 52)
    
    private static let height: CGFloat = 60
    
    private static let padding: CGFloat = (Self.height - Self.knobSize.height) * 0.5
    
    private static let snapDistance: CGFloat = 30
}

struct SwipeControl_Previews: PreviewProvider {
    static var previews: some View {
        Background(color: .backgroundMain) {
            VStack {
                Spacer()
                SwipeControl(style: .black, text: "Swipe to Pay", action: { try await Task.delay(seconds: 2) })
            }
            .padding(20)
        }
    }
}
