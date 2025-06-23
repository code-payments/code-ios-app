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
                                insertion: .opacity.combined(with: .move(edge: .top)),
                                removal: .opacity.combined(with: .move(edge: .bottom))
                            )
                        )
                }
            }
        }
        .animation(.easeInOut, value: index)
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
            "0: Will Jimmy and Sally have a girl?",
            "1: Will the Pacers win the NBA Finals?",
            "2: Will Flipcash pools launch in June?",
        ]
    )
}
