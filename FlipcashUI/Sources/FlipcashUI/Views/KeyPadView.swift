//
//  KeyPadView.swift
//  CodeUI
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import SwiftUI

public struct KeyPadView: View {
    
    @Binding var content: String
    
    public let config: Configuration
    public let rules: KeyPadRules
    
    private let columns: CGFloat = 3
    private let rows: CGFloat = 4
    
    // MARK: - Init -
    
    public init(content: Binding<String>, configuration: Configuration = .decimal(), rules: KeyPadRules = CurrencyRules()) {
        self._content = content
        self.config = configuration
        self.rules = rules
    }
    
    // MARK: - Body -
    
    public var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .center, spacing: config.spacing.height) {
                KeyPadRow(spacing: config.spacing.width) {
                    KeyPadButton(.one, style: config.style, size: size(for: config, in: geometry), action: onButton)
                    KeyPadButton(.two, style: config.style, size: size(for: config, in: geometry), action: onButton)
                    KeyPadButton(.three, style: config.style, size: size(for: config, in: geometry), action: onButton)
                }
                KeyPadRow(spacing: config.spacing.width) {
                    KeyPadButton(.four, style: config.style, size: size(for: config, in: geometry), action: onButton)
                    KeyPadButton(.five, style: config.style, size: size(for: config, in: geometry), action: onButton)
                    KeyPadButton(.six, style: config.style, size: size(for: config, in: geometry), action: onButton)
                }
                KeyPadRow(spacing: config.spacing.width) {
                    KeyPadButton(.seven, style: config.style, size: size(for: config, in: geometry), action: onButton)
                    KeyPadButton(.eight, style: config.style, size: size(for: config, in: geometry), action: onButton)
                    KeyPadButton(.nine, style: config.style, size: size(for: config, in: geometry), action: onButton)
                }
                KeyPadRow(spacing: config.spacing.width) {
                    if let content = config.leftAccessoryContent {
                        KeyPadButton(content, style: config.style, size: size(for: config, in: geometry), action: onButton)
                    } else {
                        KeyPadButton(.decimal, style: config.style, size: size(for: config, in: geometry), action: onButton)
                            .hidden()
                    }
                    
                    KeyPadButton(.zero, style: config.style, size: size(for: config, in: geometry), action: onButton)
                    
                    if let content = config.rightAccessoryContent {
                        KeyPadButton(content, style: config.style, size: size(for: config, in: geometry), action: onButton)
                    } else {
                        KeyPadButton(.decimal, style: config.style, size: size(for: config, in: geometry), action: onButton)
                            .hidden()
                    }
                }
            }
        }
        .aspectRatio(1.18, contentMode: .fit)
        .frame(maxWidth: .infinity)
    }
    
    private func size(for configuration: Configuration, in geometry: GeometryProxy) -> CGSize {
        let maxWidth = (geometry.size.width - (configuration.spacing.width * (columns + 1))) / columns
        let maxHeight = (geometry.size.height - (configuration.spacing.height * (rows - 1))) / rows
        return CGSize(
            width: max(maxWidth, 0),
            height: max(maxHeight, 0)
        )
    }
    
    private func onButton(action: ButtonAction) {
        let actuator = Actuator(content: $content, rules: rules)
        actuator.execute(action: action)
    }
}

extension KeyPadView {
    public struct Actuator {
        
        @Binding var content: String
        
        public let rules: KeyPadRules
        
        public init(content: Binding<String>, rules: KeyPadRules) {
            self._content = content
            self.rules = rules
        }
        
        @discardableResult
        public func execute(action: ButtonAction) -> Bool {
            var string = content
            
            switch action {
            case .insert(let character):
                let canIsert = rules.canInsert(character: character, content: string)
                if canIsert {
                    if string == "0" && rules.replacesZero {
                        string = character
                    } else {
                        string = "\(string)\(character)"
                    }
                } else {
                    return false
                }
                
            case .delete:
                guard let character = string.last else {
                    return false
                }
                
                let canDelete = rules.canDelete(character: String(character), content: string)
                if canDelete {
                    _ = string.popLast()
                } else {
                    return false
                }
            }
            
            content = string
            return true
        }
    }
}

// MARK: - Configuration -

extension KeyPadView {
    public struct Configuration {
        
        public let spacing: CGSize
        public let style: Style
        public let leftAccessoryContent: ButtonContent?
        public let rightAccessoryContent: ButtonContent?
        
        public static func `default`() -> Configuration {
            Configuration(
                spacing: CGSize(width: 5, height: 5),
                style: .borderless,
                leftAccessoryContent: nil,
                rightAccessoryContent: nil
            )
        }
        
        public static func decimal() -> Configuration {
            Configuration(
                spacing: CGSize(width: 5, height: 5),
                style: .borderless,
                leftAccessoryContent: .decimal,
                rightAccessoryContent: .symbol(.chveronLeft)
            )
        }
        
        public static func number() -> Configuration {
            Configuration(
                spacing: CGSize(width: 5, height: 5),
                style: .borderless,
                leftAccessoryContent: .none,
                rightAccessoryContent: .symbol(.chveronLeft)
            )
        }
    }
}

// MARK: - Rules -

public protocol KeyPadRules {
    
    var replacesZero: Bool { get }
    
    func canInsert(character: String, content: String) -> Bool
    func canDelete(character: String, content: String) -> Bool
}

// MARK: - CurrencyRules -

extension KeyPadView {
    public struct CurrencyRules: KeyPadRules {
        
        public let maxIntegerDigits: Int
        public let maxDecimalDigits: Int
        
        public var replacesZero: Bool
        
        public init(maxIntegerDigits: Int = 6, maxDecimalDigits: Int = 2, replacesZero: Bool = true) {
            self.maxIntegerDigits = maxIntegerDigits
            self.maxDecimalDigits = maxDecimalDigits
            self.replacesZero = replacesZero
        }
        
        public func canInsert(character: String, content: String) -> Bool {
            let components = content.components(separatedBy: ButtonContent.decimal.rawValue)
            
            let hasDecimal = content.contains(ButtonContent.decimal.rawValue)
            if hasDecimal {
                
                // Duplicate decimal
                if character == ButtonContent.decimal.rawValue {
                    return false
                }
                
                // Validate decimals
                if components.count > 1 {
                    let canInsertDecimal = components[1].count < maxDecimalDigits && character != ButtonContent.decimal.rawValue
                    if !canInsertDecimal {
                        return false
                    }
                }
                
            } else {
                
                // Validate digits
                if character != ButtonContent.decimal.rawValue && components.count > 0 {
                    let canInsertDigits = components[0].count < maxIntegerDigits
                    if !canInsertDigits {
                        return false
                    }
                }
            }
            
            return true
        }
        
        public func canDelete(character: String, content: String) -> Bool {
            return true
        }
    }
}

// MARK: - Style -

extension KeyPadView {
    public enum Style {
        case borderless
        case round
    }
}

// MARK: - ButtonContent -

public enum ButtonContent: RawRepresentable {
    
    case one
    case two
    case three
    case four
    case five
    case six
    case seven
    case eight
    case nine
    case zero
    case decimal
    case symbol(Symbol)
    
    public init?(rawValue: String) {
        fatalError("Unsupported operation")
    }
    
    public var rawValue: String {
        switch self {
        case .one:
            return "1"
        case .two:
            return "2"
        case .three:
            return "3"
        case .four:
            return "4"
        case .five:
            return "5"
        case .six:
            return "6"
        case .seven:
            return "7"
        case .eight:
            return "8"
        case .nine:
            return "9"
        case .zero:
            return "0"
        case .decimal:
            return Metrics.localizedDecimalSeparator
        case .symbol(let symbol):
            return symbol.rawValue
        }
    }
    
    var symbol: Symbol? {
        switch self {
        case .one, .two, .three, .four, .five, .six, .seven, .eight, .nine, .zero, .decimal:
            return nil
            
        case .symbol(let symbol):
            return symbol
        }
    }
}

// MARK: - Symbol -

extension ButtonContent {
    public enum Symbol: String {
        case chveronLeft = "chevron.left"
    }
}

// MARK: - Row -

private extension KeyPadView {
    struct KeyPadRow<Content>: View where Content: View {
        
        let spacing: CGFloat
        
        private let builder: () -> Content
        
        init(spacing: CGFloat, @ViewBuilder builder: @escaping () -> Content) {
            self.spacing = spacing
            self.builder = builder
        }
        
        var body: some View {
            HStack(alignment: .center, spacing: spacing) {
                builder()
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

// MARK: - KeyPadButton -

private extension KeyPadView {
    struct KeyPadButton: View {
        
        private let content: ButtonContent
        private let style: Style
        private let size: CGSize
        private let action: (ButtonAction) -> Void
        
        // MARK: - Init -
        
        init(_ content: ButtonContent, style: Style, size: CGSize, action: @escaping (ButtonAction) -> Void) {
            self.content = content
            self.style = style
            self.size = size
            self.action = action
        }
        
        // MARK: - Body -
        
        var body: some View {
            switch style {
            case .round:
                button(for: content)
                    .buttonStyle(KeyPadRoundStyle(size: size))
                
            case .borderless:
                button(for: content)
                    .buttonStyle(KeyPadBorderlessStyle(size: size))
            }
        }
        
        @ViewBuilder private func button(for content: ButtonContent) -> some View {
            Button {
                if let symbol = content.symbol {
                    action(for: symbol)
                } else {
                    insert(character: content.rawValue)
                }
            } label: {
                if let symbol = content.symbol {
                    Image(systemName: symbol.rawValue)
                } else {
                    Text(content.rawValue)
                }
            }
            .font(.appKeyboard)
        }
        
        // MARK: - Actions -
        
        private func insert(character: String) {
            action(.insert(character))
        }
        
        private func action(for symbol: ButtonContent.Symbol) {
            switch symbol {
            case .chveronLeft:
                deleteCharacter()
            }
        }
        
        private func deleteCharacter() {
            action(.delete)
        }
    }
}

// MARK: - Button Action -

public enum ButtonAction {
    case insert(String)
    case delete
}

// MARK: - KeyPadRoundStyle -

private struct KeyPadRoundStyle: ButtonStyle {
    
    private let size: CGSize
    
    init(size: CGSize) {
        self.size = size
    }
    
    func makeBody(configuration: Configuration) -> some View {
        configuration
            .label
            .scaleEffect(configuration.isPressed ? 1.5 : 1.0, anchor: .center)
            .frame(width: size.width, height: size.height)
            .background(configuration.isPressed ? Color.white.opacity(0.15) : Color.white.opacity(0.08))
            .foregroundColor(configuration.isPressed ? Color.white.opacity(0.5) : .white)
            .cornerRadius(45.0)
    }
}

// MARK: - KeyPadBorderlessStyle -

private struct KeyPadBorderlessStyle: ButtonStyle {
    
    private let size: CGSize
    
    init(size: CGSize) {
        self.size = size
    }
    
    func makeBody(configuration: Configuration) -> some View {
        configuration
            .label
            .scaleEffect(configuration.isPressed ? 1.5 : 1.0, anchor: .center)
            .frame(width: size.width, height: size.height) // FIXME: Invalid size here sometimes
            .background(configuration.isPressed ? Color.white.opacity(0.1) : Color.backgroundMain.opacity(0.1))
            .foregroundColor(configuration.isPressed ? Color.white.opacity(0.9) : .white)
            .cornerRadius(5.0)
    }
}

// MARK: - Previews -

struct KeypadView_Previews: PreviewProvider {    
    static var previews: some View {
        Group {
            KeyPadView(content: .constant(""), configuration: .decimal())
            .previewLayout(.fixed(width: 500, height: 340))
            
            KeyPadView(content: .constant(""), configuration: .decimal())
            .previewLayout(.fixed(width: 360, height: 200))
            
            KeyPadView(content: .constant(""), configuration: .decimal())
            .previewLayout(.fixed(width: 320, height: 320))
        }
        .background(Color.backgroundMain)
    }
}
