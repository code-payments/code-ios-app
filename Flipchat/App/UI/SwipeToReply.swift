//
//  SwipeToReply.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI
import CodeUI

public struct SwipeToReply: ViewModifier {
    
    public typealias CompletionStateBlock = (CompletionState) -> Bool
    
    public let completion: () -> Void
    
    @GestureState private var dragState: DragState = .init(offset: .zero, didTap: false, percentComplete: 0)
    
    @State private var didTap: Bool = false
    
    private let threshold: CGFloat = 42
    private let snapDistance: CGFloat = 8
    private let dragCoefficient: CGFloat = 0.3
    
    // MARK: - Init -
    
    public init(completion: @escaping () -> Void) {
        self.completion = completion
    }
    
    // MARK: - Body -
    
    public func body(content: Content) -> some View {
        content
            .overlay {
                HStack {
                    Rectangle()
                        .fill(.green)
                        .frame(width: 20, height: 20)
                        .offset(x: -30, y: 0)
                    Spacer()
                }
                .opacity(dragState.percentComplete)
            }
            .offset(dragState.offset)
            .onTapGesture {}
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($dragState) { value, state, transaction in
                        transaction.disablesAnimations = true
                        
                        var xOffset = value.translation.width * dragCoefficient
                        if xOffset > threshold - snapDistance {
                            if !state.didTap {
                                Feedback.tap()
                                state.didTap = true
                            }
                            xOffset = threshold
                        } else {
                            if state.didTap {
                                Feedback.medium()
                                state.didTap = false
                            }
                        }
                        
                        state.offset.width = max(xOffset, 0) // Prevent swipe left
                        state.percentComplete = state.offset.width / threshold
                    }
                    .onEnded { value in
//                        let state = CompletionState(
//                            velocity: CGPoint(
//                                x: value.predictedEndLocation.x - value.location.x,
//                                y: value.predictedEndLocation.y - value.location.y
//                            ),
//                            translation: value.translation
//                        )
                        
                        if value.translation.width >= threshold {
                            completion()
                        }
                    }
            )
            .animation(.spring, value: dragState.offset)
    }
}

// MARK: - CompletionState -

extension SwipeToReply {
    public struct CompletionState {
        public var velocity: CGPoint
        public var translation: CGSize
    }
}

extension SwipeToReply {
    struct DragState {
        var offset: CGSize
        var didTap: Bool
        var percentComplete: CGFloat
    }
}

// MARK: - View -

extension View {
    public func swipeToReply(completion: @escaping VoidAction) -> some View {
        modifier(
            SwipeToReply(completion: completion)
        )
    }
}
