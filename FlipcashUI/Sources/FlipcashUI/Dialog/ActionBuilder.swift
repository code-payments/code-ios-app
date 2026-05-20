//
//  Dialog+View.swift
//  FlipcashUI
//
//  Created by Dima Bart on 2025-05-06.
//

import SwiftUI

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
