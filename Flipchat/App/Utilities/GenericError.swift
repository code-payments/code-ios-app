//
//  GenericError.swift
//  Code
//
//  Created by Dima Bart on 2024-10-23.
//

struct GenericError: Error {
    
    let message: String
    let code: Int
    let underlyingError: Error?

    init(code: Int? = nil, message: String? = nil, underlyingError: Error? = nil) {
        self.message = message ?? "Operation failed"
        self.code = code ?? 500
        self.underlyingError = underlyingError
    }
    
    var localizedDescription: String {
        var description = "\(code): \(message)"
        
        if let underlyingError {
            description = "\(description). \(underlyingError)"
        }
        
        return description
    }
}
