//
//  Contact.swift
//  Code
//
//  Created by Dima Bart on 2022-02-17.
//

import Foundation
import CodeServices

struct Contact {
    let id: String
    let firstName: String?
    let lastName: String?
    let company: String?
    let phoneNumber: Phone
    var state: AppState = .unknown
}

extension Contact {
    enum AppState {
        
        case unknown
        case registered
        case invited
        
        var comparableValue: Int {
            switch self {
            case .unknown:    return 0
            case .invited:    return 1
            case .registered: return 2
            }
        }
    }
}

extension Array where Element == Contact {
    func sortedByAppState() -> [Element] {
        sorted { lhs, rhs in
            if lhs.state.comparableValue == rhs.state.comparableValue {
                return lhs.displayName < rhs.displayName
            }
            return lhs.state.comparableValue > rhs.state.comparableValue
        }
    }
}

extension Contact {
    var uniqueIdentifier: String {
        "\(id)-\(phoneNumber.e164)"
    }
    
    var displayName: String {
        if let first = firstName, let last = lastName, !first.isEmpty, !last.isEmpty {
            return "\(first) \(last)"
        } else if let first = firstName, !first.isEmpty {
            return first
        } else if let last = lastName, !last.isEmpty {
            return last
        } else if let company = company, !company.isEmpty {
            return company
        } else {
            return "Unnamed"
        }
    }
    
    var initials: String {
        if let first = firstName, let last = lastName, !first.isEmpty, !last.isEmpty {
            let f = String(first.prefix(1))
            let l = String(last.prefix(1))
            return "\(f)\(l)".uppercased()
        } else if let first = firstName, !first.isEmpty {
            return String(first.prefix(1)).uppercased()
        } else if let last = lastName, !last.isEmpty {
            return String(last.prefix(1)).uppercased()
        } else if let company = company, !company.isEmpty {
            return String(company.prefix(1)).uppercased()
        } else {
            return "X"
        }
    }
}
