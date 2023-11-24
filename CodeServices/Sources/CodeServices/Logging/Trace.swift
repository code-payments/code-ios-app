//
//  Trace.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

public enum TraceStyle: String {
    case send    = "➡️"
    case open    = "↪️"
    case poll    = "🔄"
    case success = "✅"
    case receive = "✳️"
    case note    = "📝"
    case cache   = "💰"
    case warning = "⚠️"
    case failure = "❌"
}

public func trace(_ style: TraceStyle, components: String..., function: String = #function) {
    trace(style, components: components, function: function)
}

public func trace(_ style: TraceStyle, components: [String], function: String = #function, compact: Bool = false) {
    let space = compact ? "" : "\n"
    var output = " \(style.rawValue) \(Date.timestamp)\(space)\(function)"
    
    if !components.isEmpty {
        let spacer  = compact ? " " : "      "
        let newline = compact ? " " : "\n"
        
        let modified = components.map { component in
            component
                .components(separatedBy: "\n")
                .map { line in
                    "\(spacer)\(line)"
                }
                .joined(separator: newline)
        }.joined(separator: newline)
        
        output = "\(output)\(newline)\(modified)"
    }
    
    print(output)
}

private extension Date {
    
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "(hh:mm:ss.SSSS)"
        return f
    }()
    
    static var timestamp: String {
        formatter.string(from: Date())
    }
}
