//
//  AutoUpdating.swift
//  Code
//
//  Created by Dima Bart on 2024-12-23.
//

import SwiftUI

/// Auto-refreshing wrapper that re-evaluates a database query whenever
/// `.databaseDidChange` is posted.
///
/// Use this to keep a view or model in sync with the local database without
/// manual refresh calls. The ``value`` property is tracked by `@Observable`,
/// so SwiftUI views reading it will update automatically.
@MainActor @Observable
class Updateable<T> {

    private(set) var value: T

    @ObservationIgnored private let valueBlock: () -> T
    @ObservationIgnored private let didSet: (() -> Void)?
    @ObservationIgnored private var observer: Any?

    init(_ valueBlock: @escaping () -> T, didSet: (() -> Void)? = nil) {
        self.valueBlock = valueBlock
        self.didSet = didSet

        self.value = valueBlock()

        self.observer = NotificationCenter.default.addObserver(
            forName: .databaseDidChange,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleDatabaseDidChange()
            }
        }
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func handleDatabaseDidChange() {
        value = valueBlock()
        didSet?()
    }
}
