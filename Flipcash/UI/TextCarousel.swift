//
//  TextCarousel.swift
//  Code
//
//  Created by Dima Bart on 2025-06-23.
//

import SwiftUI
import Combine

struct TextCarousel: View {
    
    let interval: TimeInterval
    let items: [Item]
    
    private let timer: Publishers.Autoconnect<Timer.TimerPublisher>
    
    @State private var index: Int = 0
    
    private var nextIndex: Int {
        if index + 1 >= items.count {
            return 0
        } else {
            return index + 1
        }
    }
    
    // MARK: - Init -
    
    init(interval: TimeInterval, items: [String]) {
        self.interval = interval
        self.items = items.enumerated().map { (index, text) in
            Item(index: index, text: text)
        }
        self.timer = Timer.publish(
            every: interval,
            on: .main,
            in: .common
        ).autoconnect()
    }
    
    // MARK: - Body -
    
    var body: some View {
        VStack {
            ForEach(items) { item in
                if item.index == index {
                    Text(item.text)
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .offset(y: -25)),
                                removal: .opacity.combined(with: .offset(y: 25))
                            )
                        )
                }
            }
        }
        .animation(.spring(dampingFraction: 0.5), value: index)
        .multilineTextAlignment(.center)
        .onReceive(timer) { input in
            index = nextIndex
        }
    }
}

extension TextCarousel {
    struct Item: Identifiable {
        
        var id: String {
            text
        }
        
        let index: Int
        let text: String
    }
}

#Preview {
    TextCarousel(
        interval: 5.0,
        items: [
            "First item in the carousel",
            "Second item in the carousel",
            "Third item in the carousel",
        ]
    )
}
