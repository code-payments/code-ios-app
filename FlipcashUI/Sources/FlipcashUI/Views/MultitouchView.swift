//
//  MultitouchView.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

#if canImport(UIKit)

import SwiftUI

public struct MultitouchView: UIViewRepresentable {
    
    public var maxTouches: Int
    
    @Binding var touches: [Touch]
    
    // MARK: - Init -
    
    init(maxTouches: Int, touches: Binding<[Touch]>) {
        self.maxTouches = maxTouches
        self._touches = touches
    }
    
    public func makeUIView(context: Context) -> some UIView {
        _MultitouchView(maxTouches: maxTouches, binding: _touches)
    }
    
    public func updateUIView(_ uiView: UIViewType, context: Context) {
        if let multitouchView = uiView as? _MultitouchView {
            multitouchView.maxTouches = maxTouches
        }
    }
}

// MARK: - Touch -

public struct Touch: Equatable {
    public let location: CGPoint
    public let tapCount: Int
    public let timestamp: TimeInterval
}

// MARK: - _MultitouchView -

final class _MultitouchView: UIView {
    
    var maxTouches: Int
    
    @Binding var binding: [Touch]
    
    private var touches: Set<UITouch> = []
    
    // MARK: - Init -
    
    required init?(coder: NSCoder) { fatalError() }

    init(maxTouches: Int, binding: Binding<[Touch]>) {
        self.maxTouches = maxTouches
        self._binding = binding
    
        super.init(frame: .zero)
        
        isMultipleTouchEnabled = true
        isExclusiveTouch = false
    }
    
    // MARK: - Touches -
    
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        return touches.isEmpty
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        
        touches.forEach {
            if self.touches.count < maxTouches {
                self.touches.insert($0)
            }
        }
        
        touchesDidChange()
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        
        touches.forEach {
            if self.touches.contains($0) {
                // Only replace captured touches
                self.touches.insert($0)
            }
        }
        
        touchesDidChange()
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        
        touches.forEach {
            self.touches.remove($0)
        }
        
        touchesDidChange()
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        
        touches.forEach {
            self.touches.remove($0)
        }
        
        touchesDidChange()
    }
    
    private func touchesDidChange() {
        let touches = touches.map {
            $0.touch
        }.sorted { lhs, rhs in
            lhs.location.x < rhs.location.x && lhs.location.y < rhs.location.y
        }
        
        binding = touches
    }
}

private extension UITouch {
    var touch: Touch {
        Touch(
            location: location(in: view),
            tapCount: tapCount,
            timestamp: timestamp
        )
    }
}

#endif
