//
//  ActionSheet.swift
//  Code
//
//  Created by Dima Bart on 2025-01-29.
//

import SwiftUI
import CodeUI

public struct ButtonSheet: View {
    
    @Binding public var isPresented: Bool
    
    public let actions: [Action]
    
    // MARK: - Init -
    
    public init(isPresented: Binding<Bool>, @ActionBuilder actions: () -> [Action]) {
        self._isPresented = isPresented
        self.actions = actions()
    }
    
    // MARK: - Body -
    
    public var body: some View {
        PartialSheet(background: .backgroundMain) {
            VStack(spacing: 0) {
                ForEach(actions, id: \.title) { action in
                    Button {
                        isPresented = false
                        Task {
                            try await action.action()
                        }
                    } label: {
                        HStack(spacing: 20) {
                            action.image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 20, height: 20)
                            
                            Text(action.title)
                                .font(.appTextMedium)
                            
                            Spacer()
                        }
                        .frame(height: 60)
                        .padding(.horizontal, 20)
                    }
                    .buttonStyle(.borderless)
                    .tint(foregroundColor(for: action))
                    .vSeparator(color: .rowSeparator, insets: .horizontal(leading: 60))
                }
            }
            .padding(.top, 2)
        }
    }
    
    private func foregroundColor(for action: Action) -> Color {
        switch action.style {
        case .standard:
            return .textMain
        case .destructive:
            return .textError
        }
    }
}

// MARK: - Action -

public struct Action {
    
    public enum Style {
        case standard
        case destructive
    }
    
    public var style: Style
    public var image: Image
    public var title: String
    public var action: () async throws -> Void
    
    fileprivate init(style: Style, image: Image, title: String, action: @escaping () async throws -> Void) {
        self.style = style
        self.image = image
        self.title = title
        self.action = action
    }
    
    public static func standard(systemImage: String, title: String, action: @escaping () async throws -> Void) -> Self {
        .standard(image: Image(systemName: systemImage), title: title, action: action)
    }
    
    public static func destructive(systemImage: String, title: String, action: @escaping () async throws -> Void) -> Self {
        .destructive(image: Image(systemName: systemImage), title: title, action: action)
    }
        
    public static func standard(image: Image, title: String, action: @escaping () async throws -> Void) -> Self {
        .init(
            style: .standard,
            image: image,
            title: title,
            action: action
        )
    }
    
    public static func destructive(image: Image, title: String, action: @escaping () async throws -> Void) -> Self {
        .init(
            style: .destructive,
            image: image,
            title: title,
            action: action
        )
    }
}

extension View {
    func buttonSheet(isPresented: Binding<Bool>, @ActionBuilder actions: @escaping () -> [Action]) -> some View {
        self.modifier(ButtonSheetModifier(isPresented: isPresented, actions: actions))
    }
}

private struct ButtonSheetModifier: ViewModifier {
    
    private let isPresented: Binding<Bool>
    private let actions: () -> [Action]
    
    init(isPresented: Binding<Bool>, actions: @escaping () -> [Action]) {
        self.isPresented = isPresented
        self.actions = actions
    }
    
    func body(content: Content) -> some View {
        content
            .sheet(isPresented: isPresented) {
                ButtonSheet(isPresented: isPresented, actions: actions)
            }
    }
}

@resultBuilder
public enum ActionBuilder {
    // Handle single Action
    public static func buildExpression(_ expression: Action) -> [Action] {
        [expression]
    }
    
    // Handle arrays of Action (e.g., from optional blocks)
    public static func buildExpression(_ expression: [Action]) -> [Action] {
        expression
    }
    
    // Combine arrays into a single array
    public static func buildBlock(_ components: [Action]...) -> [Action] {
        components.flatMap { $0 }
    }
    
    // Handle optional arrays (e.g., from `if let`)
    public static func buildOptional(_ component: [Action]?) -> [Action] {
        component ?? []
    }
    
    // Conditional logic (if/else)
    public static func buildEither(first: [Action]) -> [Action] {
        first
    }
    
    public static func buildEither(second: [Action]) -> [Action] {
        second
    }
}
