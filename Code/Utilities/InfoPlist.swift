//
//  InfoPlist.swift
//  Code
//
//  Created by Dima Bart on 2024-03-22.
//

import Foundation

enum InfoPlist {
    
    enum Value {
        
        case string(String)
        case dictionary([String: Any])
        case array([Any])
        
        func string() throws -> String {
            guard case .string(let value) = self else {
                throw InfoPlist.Error.invalidType
            }
            
            return value
        }
        
        func dictionary() throws -> [String: Any] {
            guard case .dictionary(let value) = self else {
                throw InfoPlist.Error.invalidType
            }
            
            return value
        }
        
        func array() throws -> [Any] {
            guard case .array(let value) = self else {
                throw InfoPlist.Error.invalidType
            }
            
            return value
        }
        
        init(genericValue: Any) throws {
            if let string = genericValue as? String {
                self = .string(string)
                
            } else if let dictionary = genericValue as? [String: Any] {
                self = .dictionary(dictionary)
                
            } else if let array = genericValue as? [Any] {
                self = .array(array)
                
            } else {
                throw InfoPlist.Error.invalidType
            }
        }
        
        func value(for key: String, bundle: Bundle? = nil) throws -> Value {
            switch self {
            case .array, .string:
                throw Error.invalidType
                
            case .dictionary(let dictionary):
                guard let value = dictionary[key] else {
                    throw Error.valueNotFound
                }
                
                return try Value(genericValue: value)
            }
        }
    }
    
    static func value(for key: String, bundle: Bundle? = nil) throws -> Value {
        let bundle = bundle ?? Bundle.main
        let plist = bundle.infoDictionary
        
        guard let plist else {
            throw Error.plistNotFound
        }
        
        guard let value = plist[key] else {
            throw Error.valueNotFound
        }
        
        return try Value(genericValue: value)
    }
}

extension InfoPlist {
    enum Error: Swift.Error {
        case plistNotFound
        case valueNotFound
        case invalidType
    }
}
