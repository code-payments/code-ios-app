//
//  ObservableBox.swift
//  FlipcashUI
//

import Observation

/// A single observable value, so a cache that keeps one box per key invalidates a view only when
/// its own entry changes rather than on every write to the cache.
@Observable
final class ObservableBox<Value> {
    var value: Value?

    /// A box holding `value`, empty by default.
    init(_ value: Value? = nil) {
        self.value = value
    }
}
