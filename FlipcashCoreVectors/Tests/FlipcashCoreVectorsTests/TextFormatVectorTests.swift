import Foundation
import Testing
@testable import FlipcashCore

/// `test-vectors/text_format.json` through the `TextFormat` facade. The canonical copy lives in the
/// orchestrator repo; this one is synced. The parser itself is shared Kotlin with its own suite, so
/// this checks that the Swift bridge maps offsets, styles and targets the way the fixture expects.
@Suite struct TextFormatVectorTests {

    struct Vector: Decodable, Sendable, CustomTestStringConvertible {
        struct Span: Decodable, Equatable, Sendable {
            let start: Int
            let end: Int
            let style: String
        }
        struct Range: Decodable, Equatable, Sendable {
            let start: Int
            let end: Int
            let kind: String
            let target: String?
        }
        let name: String
        let text: String
        let ranges: [Range]
        let display: String
        let spans: [Span]
        let displayRanges: [Range]
        let note: String

        var testDescription: String { name }
    }

    struct Fixture: Decodable {
        let vectors: [Vector]
    }

    static let vectors: [Vector] = (try? loadFixture().vectors) ?? []

    private static func loadFixture() throws -> Fixture {
        let url = try #require(
            Bundle.module.url(forResource: "text_format", withExtension: "json", subdirectory: "Fixtures")
        )
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
    }

    @Test func fixtureLoads() throws {
        #expect(try !Self.loadFixture().vectors.isEmpty)
    }

    @Test(arguments: vectors)
    func parseMatchesTheCrossPlatformVector(_ vector: Vector) throws {
        let protected = try vector.ranges.map { range in
            TextFormat.ProtectedRange(
                range: NSRange(location: range.start, length: range.end - range.start),
                kind: try Self.kind(range.kind)
            )
        }

        let result = TextFormat.parse(vector.text, ranges: protected)

        #expect(result.display == vector.display, "\(vector.note)")
        #expect(result.spans.map(Self.describe) == vector.spans, "\(vector.note)")
        #expect(result.displayRanges.map(Self.describe) == vector.displayRanges, "\(vector.note)")
    }

    private static func kind(_ name: String) throws -> TextFormat.RangeKind {
        switch name {
        case "link": return .link
        case "mention": return .mention
        default: throw FixtureError.unknownKind(name)
        }
    }

    private static func describe(_ span: TextFormat.Span) -> Vector.Span {
        let style: String
        switch span {
        case .bold: style = "bold"
        case .italic: style = "italic"
        case .strike: style = "strike"
        case .code: style = "code"
        case .codeBlock: style = "codeBlock"
        case .quote: style = "quote"
        case .bullet: style = "bullet"
        case .numbered: style = "numbered"
        }
        return Vector.Span(start: span.range.location, end: NSMaxRange(span.range), style: style)
    }

    private static func describe(_ range: TextFormat.DisplayRange) -> Vector.Range {
        Vector.Range(
            start: range.range.location,
            end: NSMaxRange(range.range),
            kind: range.kind == .link ? "link" : "mention",
            target: range.target?.absoluteString
        )
    }

    private enum FixtureError: Error {
        case unknownKind(String)
    }
}
