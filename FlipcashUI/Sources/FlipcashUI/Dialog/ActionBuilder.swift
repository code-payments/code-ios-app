//
//  ActionBuilder.swift
//  FlipcashUI
//
//  Created by Dima Bart on 2025-05-06.
//

import SwiftUI

@resultBuilder
public enum ActionBuilder {
    public static func buildExpression(_ expression: DialogAction) -> [DialogAction] {
        [expression]
    }

    public static func buildExpression(_ expression: [DialogAction]) -> [DialogAction] {
        expression
    }

    public static func buildBlock(_ components: [DialogAction]...) -> [DialogAction] {
        components.flatMap { $0 }
    }

    public static func buildOptional(_ component: [DialogAction]?) -> [DialogAction] {
        component ?? []
    }

    public static func buildEither(first: [DialogAction]) -> [DialogAction] {
        first
    }

    public static func buildEither(second: [DialogAction]) -> [DialogAction] {
        second
    }
}
