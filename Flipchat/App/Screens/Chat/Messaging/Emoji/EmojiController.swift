//
//  EmojiController.swift
//  Code
//
//  Created by Dima Bart on 2025-03-19.
//

import Foundation
@preconcurrency import SQLite

struct EmojiTable: Sendable {
    static let name = "emoji"
    
    let symbol      = Expression<String> ("symbol")
    let code        = Expression<String> ("code")
    let name        = Expression<String> ("name")
    let shortNames  = Expression<String> ("short_names")
    let sortOrder   = Expression<Int>    ("sort_order")
    let categoryID  = Expression<Int>    ("category_id")
    let subcategory = Expression<String> ("subcategory")
    let annotations = Expression<String> ("annotations")
}

struct CategoryTable: Sendable {
    static let name = "category"
    
    let id   = Expression<Int>    ("id")
    let name = Expression<String> ("name")
}

struct Emoji {
    let symbol: String
    let name: String
    let shortName: String
    
    init(symbol: String, name: String, shortName: String) {
        self.symbol    = symbol
        self.name      = name
        self.shortName = shortName.replacingUnderscoresWithSpaces()
    }
}

struct EmojiGroup {
    
    let name: String
    let sortOrder: Int
    var emojis: [Emoji]
    
    init(name: String, sortOrder: Int, emojis: [Emoji]) {
        self.name = name
        self.sortOrder = sortOrder
        self.emojis = emojis
    }
}

class EmojiController: ObservableObject {
    
    @Published var emojis: [EmojiGroup] = []
    
    private let db: Connection
    
    init() throws {
        let url = Bundle.main.url(forResource: "emoji", withExtension: "sqlite")!
        db = try Connection(url.path, readonly: true)
        emojis = try fetchAll()
    }
    
    func fetchAll() throws -> [EmojiGroup] {
        let statement = try db.prepareRowIterator("""
        SELECT 
            e.symbol,
            e.name,
            e.short_names,
            c.name AS categoryName
        FROM 
            emoji e
        LEFT JOIN 
            category c ON e.category_id = c.id
        ORDER BY 
            sort_order;
        """)
        
        let eTable = EmojiTable()
        let categoryName = Expression<String>("categoryName")
        
        let excludedCategories: Set<String> = [
            "Component",
        ]
        
        var groups: [String: EmojiGroup] = [:]
        
        _ = try statement.map { row in
            let category = row[categoryName]
            let emoji    = Emoji(
                symbol:       row[eTable.symbol],
                name:         row[eTable.name],
                shortName:    row[eTable.shortNames]
            )
            
            guard !excludedCategories.contains(category) else {
                return emoji
            }
            
            if var group = groups[category] {
                group.emojis.append(emoji)
                groups[category] = group
            } else {
                groups[category] = EmojiGroup(
                    name: category,
                    sortOrder: groups.count,
                    emojis: [emoji]
                )
            }
            
            return emoji
        }
        
        return groups.values.sorted { lhs, rhs in
            lhs.sortOrder < rhs.sortOrder
        }
    }
    
    func search(term: String) throws -> [Emoji] {
        let s = ""
        let fuzzyTerm = term
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: s)
            .map { "\($0)*" }
            .joined(separator: s)
        
        let statement = try db.prepareRowIterator("""
        SELECT 
            e.symbol,
            e.name,
            e.short_names
        FROM 
            emoji_fts e
        WHERE emoji_fts MATCH ? 
        ORDER BY rank;
        """, bindings: fuzzyTerm)
        
        let eTable = EmojiTable()
        
        let results = try statement.map { row in
            Emoji(
                symbol:    row[eTable.symbol],
                name:      row[eTable.name],
                shortName: row[eTable.shortNames]
            )
        }
        
        return results
    }
}

extension String {
    func replacingUnderscoresWithSpaces() -> String {
        self
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: ",", with: ", ")
    }
}
