//
//  AutoReturnTimeout.swift
//  FlipcashCore
//
//  Created by Raul Riera on 2026-05-08.
//

import Foundation

/// User-selected duration after which the app returns to the Scanner on
/// next foreground. Mirrors iOS Auto-Lock semantics: a small set of fixed
/// durations plus an opt-out.
public enum AutoReturnTimeout: String, CaseIterable, Codable, Sendable {
    case fiveMinutes = "five-minutes"
    case tenMinutes  = "ten-minutes"
    case never       = "never"

    /// `nil` for ``never``. Callers treat `nil` as "skip the auto-return entirely".
    public var duration: TimeInterval? {
        switch self {
        case .fiveMinutes: return 5 * 60
        case .tenMinutes:  return 10 * 60
        case .never:       return nil
        }
    }

    /// User-facing label. Matches the iOS Auto-Lock copy.
    public var displayName: String {
        switch self {
        case .fiveMinutes: return "5 Minutes"
        case .tenMinutes:  return "10 Minutes"
        case .never:       return "Never"
        }
    }
}
