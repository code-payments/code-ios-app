//
//  Dialog+View.swift
//  FlipcashUI
//
//  Created by Dima Bart on 2025-05-06.
//

import SwiftUI

extension View {
    public func dialog(isPresented: Binding<Bool>, style: Dialog.Style, title: String?, subtitle: String?, dismissable: Bool = false, @ActionBuilder actions: @escaping () -> [DialogAction]) -> some View {
        self.modifier(
            DialogModifierBoolean(
                isPresented: isPresented,
                style: style,
                title: title,
                subtitle: subtitle,
                dismissable: dismissable,
                actions: actions
            )
        )
    }
    
    public func dialog<T>(item: Binding<T?>, style: Dialog.Style, title: String?, subtitle: String?, dismissable: Bool = false, @ActionBuilder actions: @escaping (T) -> [DialogAction]) -> some View where T: Identifiable {
        self.modifier(
            DialogModifierItem(
                item: item,
                style: style,
                title: title,
                subtitle: subtitle,
                dismissable: dismissable,
                actions: actions
            )
        )
    }
    
    public func dialog(item: Binding<DialogItem?>) -> some View {
        self.modifier(
            DialogModifierDialogItem(item: item)
        )
    }
}

// MARK: - DialogItem -

public struct DialogItem: Identifiable {
    
    public let id: UUID
    public let style: Dialog.Style
    public let title: String?
    public let subtitle: String?
    public let dismissable: Bool
    public let actions: [DialogAction]
    
    public init(style: Dialog.Style, title: String?, subtitle: String?, dismissable: Bool, @ActionBuilder actions: () -> [DialogAction]) {
        self.id          = UUID()
        self.style       = style
        self.title       = title
        self.subtitle    = subtitle
        self.dismissable = dismissable
        self.actions     = actions()
    }
}

// MARK: - Modifiers -

private struct DialogModifierBoolean: ViewModifier {
    
    private let isPresented: Binding<Bool>
    private let style: Dialog.Style
    private let title: String?
    private let subtitle: String?
    private let dismissable: Bool
    private let actions: () -> [DialogAction]
    
    init(isPresented: Binding<Bool>, style: Dialog.Style, title: String?, subtitle: String?, dismissable: Bool, actions: @escaping () -> [DialogAction]) {
        self.isPresented = isPresented
        self.style       = style
        self.title       = title
        self.subtitle    = subtitle
        self.dismissable = dismissable
        self.actions     = actions
    }
    
    func body(content: Content) -> some View {
        content
            .sheet(isPresented: isPresented) {
                PartialSheet(background: style.backgroundColor, canDismiss: dismissable) {
                    Dialog(
                        style: style,
                        title: title,
                        subtitle: subtitle,
                        dismiss: dismiss,
                        actions: actions()
                    )
                }
            }
    }
    
    private func dismiss() {
        isPresented.wrappedValue = false
    }
}

private struct DialogModifierItem<T>: ViewModifier where T: Identifiable {
    
    private let item: Binding<T?>
    private let style: Dialog.Style
    private let title: String?
    private let subtitle: String?
    private let dismissable: Bool
    private let actions: (T) -> [DialogAction]
    
    init(item: Binding<T?>, style: Dialog.Style, title: String?, subtitle: String?, dismissable: Bool, actions: @escaping (T) -> [DialogAction]) {
        self.item        = item
        self.style       = style
        self.title       = title
        self.subtitle    = subtitle
        self.dismissable = dismissable
        self.actions     = actions
    }
    
    func body(content: Content) -> some View {
        content
            .sheet(item: item) { item in
                PartialSheet(background: style.backgroundColor, canDismiss: dismissable) {
                    Dialog(
                        style: style,
                        title: title,
                        subtitle: subtitle,
                        dismiss: dismiss,
                        actions: actions(item)
                    )
                }
            }
    }
    
    private func dismiss() {
        item.wrappedValue = nil
    }
}

private struct DialogModifierDialogItem: ViewModifier {
    
    private let item: Binding<DialogItem?>
    
    init(item: Binding<DialogItem?>) {
        self.item = item
    }
    
    func body(content: Content) -> some View {
        content
            .sheet(item: item) { item in
                PartialSheet(background: item.style.backgroundColor, canDismiss: item.dismissable) {
                    Dialog(
                        style: item.style,
                        title: item.title,
                        subtitle: item.subtitle,
                        dismiss: dismiss,
                        actions: item.actions
                    )
                }
            }
    }
    
    private func dismiss() {
        item.wrappedValue = nil
    }
}

// MARK: - ActionBuilder -

@resultBuilder
public enum ActionBuilder {
    // Handle single Action
    public static func buildExpression(_ expression: DialogAction) -> [DialogAction] {
        [expression]
    }
    
    // Handle arrays of Action (e.g., from optional blocks)
    public static func buildExpression(_ expression: [DialogAction]) -> [DialogAction] {
        expression
    }
    
    // Combine arrays into a single array
    public static func buildBlock(_ components: [DialogAction]...) -> [DialogAction] {
        components.flatMap { $0 }
    }
    
    // Handle optional arrays (e.g., from `if let`)
    public static func buildOptional(_ component: [DialogAction]?) -> [DialogAction] {
        component ?? []
    }
    
    // Conditional logic (if/else)
    public static func buildEither(first: [DialogAction]) -> [DialogAction] {
        first
    }
    
    public static func buildEither(second: [DialogAction]) -> [DialogAction] {
        second
    }
}
