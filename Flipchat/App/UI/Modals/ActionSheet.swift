//
//  ActionSheet.swift
//  Code
//
//  Created by Dima Bart on 2025-01-29.
//

import SwiftUI
import CodeUI

public struct ButtonSheet: View {
    
    public let dismissHandler: () -> Void
    public let actions: [Action]
    
    // MARK: - Init -
    
    public init(dismissHandler: @escaping () -> Void, @ActionBuilder actions: () -> [Action]) {
        self.dismissHandler = dismissHandler
        self.actions = actions()
    }
    
    public init<T>(item: T, dismissHandler: @escaping () -> Void, @ActionBuilder actions: (T) -> [Action]) where T: Identifiable {
        self.dismissHandler = dismissHandler
        self.actions = actions(item)
    }
    
    // MARK: - Body -
    
    public var body: some View {
        PartialSheet(background: .backgroundMain) {
            VStack(spacing: 0) {
                ForEach(actions, id: \.title) { action in
                    Button {
                        dismissHandler()
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
        self.modifier(ButtonSheetModifierBoolean(isPresented: isPresented, actions: actions))
    }
    
    func buttonSheet<T>(item: Binding<T?>, @ActionBuilder actions: @escaping (T) -> [Action]) -> some View where T: Identifiable {
        self.modifier(ButtonSheetModifierItem(item: item, actions: actions))
    }
}

private struct ButtonSheetModifierBoolean: ViewModifier {
    
    private let isPresented: Binding<Bool>
    private let actions: () -> [Action]
    
    init(isPresented: Binding<Bool>, actions: @escaping () -> [Action]) {
        self.isPresented = isPresented
        self.actions = actions
    }
    
    func body(content: Content) -> some View {
        content
            .sheet(isPresented: isPresented) {
                ButtonSheet(dismissHandler: dismiss, actions: actions)
            }
    }
    
    private func dismiss() {
        isPresented.wrappedValue = false
    }
}

private struct ButtonSheetModifierItem<T>: ViewModifier where T: Identifiable {
    
    private let item: Binding<T?>
    private let actions: (T) -> [Action]
    
    init(item: Binding<T?>, actions: @escaping (T) -> [Action]) {
        self.item = item
        self.actions = actions
    }
    
    func body(content: Content) -> some View {
        content
            .sheet(item: item) { item in
                ButtonSheet(
                    item: item,
                    dismissHandler: dismiss,
                    actions: actions
                )
            }
    }
    
    private func dismiss() {
        item.wrappedValue = nil
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
