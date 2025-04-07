//
//  Draggable.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI

public struct Draggable: ViewModifier {
    
    public typealias CompletionStateBlock = (CompletionState) -> Bool
    
    public let axis: Axis
    public let dragCoefficient: CGFloat
    public let shouldComplete: CompletionStateBlock?
    public let completion: VoidAction
    
    @GestureState private var offset: CGSize = .zero
    
    // MARK: - Init -
    
    public init(axis: Axis, dragCoefficient: CGFloat = 0.7, shouldComplete: CompletionStateBlock?, completion: @escaping VoidAction) {
        self.axis = axis
        self.dragCoefficient = dragCoefficient
        self.shouldComplete = shouldComplete
        self.completion = completion
    }
    
    // MARK: - Body -
    
    public func body(content: Content) -> some View {
        content
            .offset(offset)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($offset) { value, state, transaction in
                        transaction.disablesAnimations = true
                        state.width  = axis.contains(.horizontal) ? value.translation.width  * dragCoefficient : 0
                        state.height = axis.contains(.vertical)   ? value.translation.height * dragCoefficient : 0
                    }
                    .onEnded { value in
                        let state = CompletionState(
                            velocity: CGPoint(
                                x: value.predictedEndLocation.x - value.location.x,
                                y: value.predictedEndLocation.y - value.location.y
                            ),
                            translation: value.translation
                        )
                        
                        if shouldComplete?(state) ?? true {
                            completion()
                        }
                    }
            )
    }
}

// MARK: - Axis -

extension Draggable {
    public struct Axis: OptionSet, Sendable {
        public static let horizontal = Axis(rawValue: 1 << 0)
        public static let vertical   = Axis(rawValue: 1 << 1)
        
        public let rawValue: Int
        
        public init(rawValue: Int) {
            self.rawValue = rawValue
        }
    }
}

extension Draggable {
    public struct CompletionState {
        public var velocity: CGPoint
        public var translation: CGSize
    }
}

// MARK: - View -

extension View {
    public func draggable(axis: Draggable.Axis, dragCoefficient: CGFloat = 0.7, shouldComplete: Draggable.CompletionStateBlock? = nil, completion: @escaping VoidAction) -> some View {
        modifier(
            Draggable(
                axis: axis,
                dragCoefficient: dragCoefficient,
                shouldComplete: shouldComplete,
                completion: completion
            )
        )
    }
}
