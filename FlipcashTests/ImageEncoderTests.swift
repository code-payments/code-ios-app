//
//  ImageEncoderTests.swift
//  FlipcashTests
//

import Testing
import UIKit
@testable import Flipcash

@Suite("ImageEncoder")
struct ImageEncoderTests {

    @Test("encode returns data within byte budget for a simple image")
    func encode_simpleImage_withinBudget() async throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 500, height: 500))
        let image = renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 500, height: 500))
        }

        let data = try await ImageEncoder.encodeForUpload(image, maxBytes: 1_048_576)

        #expect(data.count <= 1_048_576)
        #expect(UIImage(data: data) != nil)
    }

    @Test("encode downsizes a large image to stay under budget")
    func encode_largeImage_downsizesUnderBudget() async throws {
        // 4000x4000 image filled with noise is typically >1MB as JPEG
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 4000, height: 4000))
        let image = renderer.image { context in
            for y in stride(from: 0, to: 4000, by: 4) {
                for x in stride(from: 0, to: 4000, by: 4) {
                    UIColor(red: .random(in: 0...1),
                            green: .random(in: 0...1),
                            blue: .random(in: 0...1),
                            alpha: 1).setFill()
                    context.fill(CGRect(x: x, y: y, width: 4, height: 4))
                }
            }
        }

        let data = try await ImageEncoder.encodeForUpload(image, maxBytes: 1_048_576)

        #expect(data.count <= 1_048_576)
        #expect(UIImage(data: data) != nil)
    }
}
