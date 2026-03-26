//
//  Trace.swift
//  FlipcashCore
//
//  Bridge: delegates to swift-log Logger. Will be deleted
//  once all call sites are migrated to Logger directly.
//

import Foundation
import Logging

public enum TraceStyle: String, Sendable {
    case send    = "➡️"
    case open    = "↪️"
    case close   = "↩️"
    case poll    = "🔄"
    case success = "✅"
    case receive = "✳️"
    case note    = "📝"
    case cache   = "💰"
    case warning = "⚠️"
    case failure = "❌"
    case write   = "💿"

    var loggerLevel: Logger.Level {
        switch self {
        case .failure:                          .error
        case .warning:                          .warning
        case .success, .receive, .send,
             .open, .close:                     .info
        case .poll, .cache, .write, .note:      .debug
        }
    }
}

private let traceLogger = Logger(label: "flipcash.trace")

public func trace(_ style: TraceStyle, components: String..., function: String = #function) {
    trace(style, components: components, function: function)
}

public func trace(_ style: TraceStyle, components: [String], function: String = #function, compact: Bool = false) {
    let level = style.loggerLevel
    let message = Logger.Message(stringLiteral: components.joined(separator: " "))
    traceLogger.log(level: level, message, source: function)
}
