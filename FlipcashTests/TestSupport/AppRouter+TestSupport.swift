//
//  AppRouter+TestSupport.swift
//  FlipcashTests
//
//  Created by Raul Riera on 2026-04-27.
//

import SwiftUI
@testable import Flipcash

extension AppRouter {

    /// Builds a `NavigationPath` from a typed sequence of `Destination`s.
    /// Used in tests to assert against `router[.<stack>]`.
    @MainActor
    static func navigationPath(_ destinations: AppRouter.Destination...) -> NavigationPath {
        var path = NavigationPath()
        for destination in destinations { path.append(destination) }
        return path
    }
}
