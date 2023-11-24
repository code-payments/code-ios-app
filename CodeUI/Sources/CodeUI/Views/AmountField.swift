//
//  AmountField.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI
import CodeServices

public struct AmountField: View {
    
    @Binding public var content: String
    
    public let defaultValue: String
    public let flagStyle: Flag.Style
    public let formatter: NumberFormatter
    public let suffix: String?
    
    private let spacing: CGFloat = 15
    private let insertionOffset: CGFloat = 30
    
    private var hasValue: Bool {
        content.count > 0
    }
    
    // MARK: - Init -
    
    public init(content: Binding<String>, defaultValue: String, flagStyle: Flag.Style, formatter: NumberFormatter, suffix: String? = nil) {
        self._content = content
        self.defaultValue = defaultValue
        self.flagStyle = flagStyle
        self.formatter = formatter
        self.suffix = (suffix == nil) ? nil : " \(suffix!)" 
    }
    
    public var body: some View {
        HStack(spacing: spacing) {
            HStack(spacing: 5) {
                Flag(style: flagStyle)
                    .transition(
                        AnyTransition
                            .opacity
                            .combined(with: .move(edge: .leading))
                            .animation(.easeOutFastest)
                    )
                Image.system(.chevronDown)
                    .font(.default(size: 12, weight: .bold))
            }
            .animation(.springFastestDamped)
            
            HStack(spacing: 0) {
                ForEach(chars(content: content), id: \.id) { char in
                    Text(char.value)
                        .opacity(char.isGhost ? 0.2 : 1.0)
                        .transition(transition(for: char))
                        .animation(.springFastestDamped)
                }
            }
            .minimumScaleFactor(0.1)
            .scaledToFit()
            .font(.appDisplayLarge)
            .frame(height: 70.0) // Height must match font
        }
    }
    
    private func transition(for char: Char) -> AnyTransition {
        if char.isNumeric {
            return AnyTransition
                .opacity
                .combined(with: .offset(x: 0, y: hasValue ? -insertionOffset : insertionOffset))
                .animation(.easeOutFastest)
        } else {
            return AnyTransition
                .opacity
                .animation(.easeOutFastest)
        }
    }
    
    private func chars(content: String) -> [Char] {
        var characters: [Char] = []
        
        // Integers
        
        let components = content.components(separatedBy: ButtonContent.decimal.rawValue)
        if components.count > 0, components[0].count > 0, let formattedIntegers = formatter.string(byConvertingString: components[0]) {
            formattedIntegers.forEach {
                characters.append(
                    Char(
                        direction: .forward,
                        value: String($0),
                        isGhost: false
                    )
                )
            }
            
        } else {
            let integers = formatter.string(byConvertingString: defaultValue)!
            integers.forEach {
                characters.append(
                    Char(
                        direction: .forward,
                        value: String($0),
                        isGhost: false
                    )
                )
            }
        }
        
        // Decimals
        
        let hasDecimals = components.count > 1
        if hasDecimals {
            characters.append(
                Char(
                    direction: .forward,
                    value: ButtonContent.decimal.rawValue,
                    isGhost: false
                )
            )
            
            var decimals = components[1].map {
                Char(
                    direction: .forward,
                    value: String($0),
                    isGhost: false
                )
            }
            
            // Fill in any remaining decimals that
            // are missing from the formatted version
            while decimals.count < 2 {
                decimals.append(
                    Char(
                        direction: .backward,
                        value: "0",
                        isGhost: true
                    )
                )
            }
            
            characters.append(contentsOf: decimals)
        }
        
        // Insert suffix characters individually
        // one at a time
        if let suffix = suffix {
            let suffixCharacters = suffix.map {
                Char(
                    direction: .backward,
                    value: String($0),
                    isGhost: false
                )
            }
            characters.append(contentsOf: suffixCharacters)
        }
        
        // Update all grouping separators to index backwards
        // so that animations are smoother and more accurate
        characters = characters.map { char in
            if char.value == formatter.groupingSeparator {
                return char.direction(.backward)
            } else {
                return char
            }
        }
        
        return assigningIDs(to: characters)
    }
    
    private func assigningIDs(to characters: [Char]) -> [Char] {
        /*
         It's important to tag each repeated character in the order
         that it appears to ensure that animations don't add / remove
         characters that are already in place.
         */
        var chars: [Char] = characters

        var lookupTable: [String: Int] = [:]
        
        chars = chars.reversed().map { char in
            guard char.direction == .backward else {
                return char
            }
            
            let count = lookupTable[char.id] ?? 0
            lookupTable[char.id] = count + 1
            return char.occuring(count)
        }.reversed()
                
        chars = chars.map { char in
            guard char.direction == .forward else {
                return char
            }
            
            let count = lookupTable[char.id] ?? 0
            lookupTable[char.id] = count + 1
            return char.occuring(count)
        }

//        print(chars.map { $0.id })
        return chars
    }
}

// MARK: - Char -

private extension AmountField {
    struct Char {
        
        var id: String {
            "\(value)\(isGhost ? "g" : "") - \(direction.rawValue)\(occurance)"
        }
        
        let direction: IndexingDirection
        let value: String
        let isGhost: Bool
        let occurance: Int
        
        init(direction: IndexingDirection, value: String, isGhost: Bool, occurance: Int = 0) {
            self.direction = direction
            self.value = value
            self.isGhost = isGhost
            self.occurance = occurance
        }
        
        var isNumeric: Bool {
            switch value {
            case "1", "2", "3", "4", "5", "6", "7", "8", "9", "0":
                return true
            default:
                return false
            }
        }
        
        func direction(_ direction: IndexingDirection) -> Char {
            Char(
                direction: direction,
                value: value,
                isGhost: isGhost,
                occurance: occurance
            )
        }
        
        func occuring(_ occurance: Int) -> Char {
            Char(
                direction: direction,
                value: value,
                isGhost: isGhost,
                occurance: occurance
            )
        }
    }
}

private extension AmountField.Char {
    enum IndexingDirection: String {
        case forward  = "f"
        case backward = "b"
    }
}

// MARK: - Previews -

struct AmountField_Previews: PreviewProvider {
    static let suffix = " of Kin"
    static var previews: some View {
        Group {
//            VStack {
//                Animator()
//            }
//            .padding(20.0)
//            .previewLayout(.fixed(width: 300, height: 150))
            
            AmountField(content: .constant("122"), defaultValue: "0", flagStyle: .fiat(.us), formatter: .fiat(currency: .usd), suffix: suffix)
                .previewLayout(.fixed(width: 450, height: 100))
            AmountField(content: .constant("123456"), defaultValue: "0", flagStyle: .fiat(.us), formatter: .fiat(currency: .usd), suffix: suffix)
                .previewLayout(.fixed(width: 450, height: 100))
            AmountField(content: .constant("1234567890"), defaultValue: "0", flagStyle: .fiat(.us), formatter: .fiat(currency: .usd), suffix: suffix)
                .previewLayout(.fixed(width: 450, height: 100))
        }
    }
}

// MARK: - Animator -

private extension AmountField_Previews {
    struct Animator: View {
        
        private static let startValue:     String = "122"
        private static let endValue:       String = "1224"
        
        @State var content: String = Animator.startValue
        
        var body: some View {
            AmountField(content: $content, defaultValue: "0", flagStyle: .fiat(.us), formatter: .fiat(currency: .usd))
                .onAppear {
                    appendCharacter()
                }
        }
        
        private func appendCharacter() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if content > Animator.startValue {
                    content = Animator.startValue
                } else {
                    content = Animator.endValue
                }
                appendCharacter()
            }
        }
    }
}
