//
//  EmojiGenerator.swift
//  Code
//
//  Created by Dima Bart on 2025-03-18.
//

import Foundation
@preconcurrency import SQLite

class EmojiGenerator {
    
    private let db: Connection
    
    private let url = URL(string: "https://raw.githubusercontent.com/iamcal/emoji-data/refs/heads/master/emoji_pretty.json")!
    private let annotationsURL = URL(string: "https://raw.githubusercontent.com/unicode-org/cldr-json/main/cldr-json/cldr-annotations-full/annotations/en/annotations.json")!
    
    private let emoji       = Table("emoji")
    private let symbol      = SQLite.Expression<String> ("symbol")
    private let code        = SQLite.Expression<String> ("code")
    private let name        = SQLite.Expression<String> ("name")
    private let shortNames  = SQLite.Expression<String> ("short_names")
    private let sortOrder   = SQLite.Expression<Int>    ("sort_order")
    private let categoryID  = SQLite.Expression<Int>    ("category_id")
    private let subcategory = SQLite.Expression<String> ("subcategory")
    private let annotations = SQLite.Expression<String> ("annotations")
    
    private let category  = Table("category")
    private let id        = SQLite.Expression<Int>("id")
    
    private let emojiFTS  = VirtualTable("emoji_fts")
    
    private let decoder = JSONDecoder()
    
    init(databasePath: String) throws {
        db = try Connection(databasePath)
        try createTable()
    }
    
    private func createTable() throws {
        try db.run(category.create(ifNotExists: true) { t in
            t.column(id, primaryKey: true)
            t.column(name, unique: true)
        })
        
        try db.run(emoji.create(ifNotExists: true, withoutRowid: true) { t in
            t.column(symbol, primaryKey: true)
            t.column(code)
            t.column(name)
            t.column(shortNames)
            t.column(sortOrder)
            t.column(categoryID, references: category, id)
            t.column(subcategory)
            t.column(annotations)
        })
        
        let config = FTS5Config()
            .column(symbol)
            .column(name)
            .column(shortNames)
            .column(annotations)
            
        try db.run(emojiFTS.create(.FTS5(config), ifNotExists: true))
        
        try db.run(emoji.createIndex(code,        ifNotExists: true))
        try db.run(emoji.createIndex(shortNames,  ifNotExists: true))
        try db.run(emoji.createIndex(sortOrder,   ifNotExists: true))
        try db.run(emoji.createIndex(categoryID,  ifNotExists: true))
        try db.run(emoji.createIndex(subcategory, ifNotExists: true))
        try db.run(emoji.createIndex(annotations, ifNotExists: true))
    }
    
    func generate() async throws {
        print("Downloading emoji set...")
        let s1 = Date()
        let emojiSet = try await downloadEmojiSet()
        print("Done: \(Date.now.timeIntervalSince1970 - s1.timeIntervalSince1970) s")
        
        print("Downloading annotations...")
        let s2 = Date()
        let annotationsMap = try await downloadAnnotationData()
        print("Done: \(Date.now.timeIntervalSince1970 - s2.timeIntervalSince1970) s")
        print("Annotations available for \(annotationsMap.count) emojis")
        
        print("Inserting...")
        let s3 = Date()
        try db.transaction {
            
            var categoryMap: [String: Int64] = [:]
            for item in emojiSet {
                if let categoryName = item.category, !categoryName.isEmpty, categoryMap[categoryName] == nil {
                    let insertedID = try db.run(category.insert(
                        name <- categoryName
                    ))
                    categoryMap[categoryName] = insertedID
                }
            }
            
            var unmatchedCount = 0
            for item in emojiSet {
                
                let categoryValue    = item.category.flatMap { categoryMap[$0] } ?? -1
                let emojiSymbol      = item.code.toEmoji().normalized
                let annotationString = annotationsMap[emojiSymbol] ?? ""
                
                if annotationString.isEmpty {
                    unmatchedCount += 1
                }
                
                let emojiName = item.name ?? ""
                let shortName = item.short_names.joined(separator: ",")
                
                try db.run(emoji.insert(
                    name        <- emojiName,
                    symbol      <- emojiSymbol,
                    code        <- item.code.removingVariationModifiers,
                    shortNames  <- shortName,
                    sortOrder   <- item.sort_order,
                    categoryID  <- Int(categoryValue),
                    subcategory <- item.subcategory ?? "",
                    annotations <- annotationString
                ))
                
                try db.run(emojiFTS.insert(
                    name        <- emojiName,
                    shortNames  <- shortName,
                    symbol      <- emojiSymbol,
                    annotations <- annotationString
                ))
            }
            print("Unmatched emojis: \(unmatchedCount) out of \(emojiSet.count)")
        }
        print("Inserted: \(emojiSet.count)")
        print("Done: \(Date.now.timeIntervalSince1970 - s3.timeIntervalSince1970) s")
    }
    
    private func downloadEmojiSet() async throws -> [Emoji] {
        let (data, _)  = try await URLSession.shared.data(from: url)
        let collection = try decoder.decode([Emoji].self, from: data)
        
        return collection
    }
    
    private func downloadAnnotationData() async throws -> [String: String] {
        let (data, _) = try await URLSession.shared.data(from: annotationsURL)
        
        let annotationsCollection = try decoder.decode(AnnotationsRoot.self, from: data)
        let annotationsMap = annotationsCollection.annotations.annotations
            .mapValues { $0.default?.joined(separator: ",") ?? "" }
            .mapKeys { $0.normalized }
        
        return annotationsMap
    }
}

extension String {
    func toEmoji() -> String {
        let codePoints = self.split(separator: "-").compactMap { UInt32($0, radix: 16) }
        let scalars = codePoints.compactMap { UnicodeScalar($0) }
        return String(scalars.map(Character.init))
    }
    
    var normalized: String {
        let nfc = self.precomposedStringWithCanonicalMapping
        return nfc.removingVariationModifiers
    }
    
    var removingVariationModifiers: String {
        self
            .replacingOccurrences(of: "\u{FE0F}", with: "")
            .replacingOccurrences(of: "\u{FE0E}", with: "")
    }
}

extension Dictionary {
    func mapKeys<T>(transform: (Key) -> T) -> [T: Value] {
        var result: [T: Value] = [:]
        for (key, value) in self {
            result[transform(key)] = value
        }
        return result
    }
}

// MARK: - Types -

extension EmojiGenerator {
    struct Emoji: Codable {
        let name: String?
        let unified: String
        let non_qualified: String?
        let short_names: [String]
        let sort_order: Int
        let category: String?
        let subcategory: String?
        
        var code: String {
            non_qualified ?? unified
        }
    }
    
    struct AnnotationsRoot: Codable {
        let annotations: AnnotationsFull
        
        struct AnnotationsFull: Codable {
            let annotations: [String: Annotation]
        }
        
        struct Annotation: Codable {
            let `default`: [String]?
            let tts: [String]?
        }
    }
    
    enum EmojiError: Error {
        case downloadFailed
        case parsingFailed
    }
}

// MARK: - App -

@main
struct App {
    static func main() async throws {
        let path = NSSearchPathForDirectoriesInDomains(.desktopDirectory, .userDomainMask, true).first! + "/emoji.sqlite"
        let manager = try EmojiGenerator(databasePath: path)
        try await manager.generate()
    }
}
