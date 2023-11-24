//
//  MnemonicTests.swift
//  CodeServicesTests
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import XCTest
import CodeServices

class MnemonicTests: XCTestCase {
    
    let testCases = [
        (
            phrase: "sting afraid shoe",
            entropy: Data(fromHexEncodedString: "d5e09319")!
        ),
        (
            phrase: "fantasy fever angle fish soon brisk",
            entropy: Data(fromHexEncodedString: "530aac232bdcf438")!
        ),
        (
            phrase: "birth sword flower jar clerk already cake token hedgehog",
            entropy: Data(fromHexEncodedString: "16bb89663ba2a60e48171f6a")!
        ),
        (
            phrase: "abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about",
            entropy: Data(repeating: 0, count: 16)
        ),
        (
            phrase: "rally speed budget undo purpose orchard hero news crunch flush wine finger",
            entropy: Data(fromHexEncodedString: "b15a2076767ae7381ad4a934eb3bee2b")!
        ),
        (
            phrase: "mammal crunch speed person arctic claw wolf chef crisp mirror program slim isolate behave object",
            entropy: Data(fromHexEncodedString: "86a69f4451a0b2543f313a33b1b2afe5e76828e6")!
        ),
        (
            phrase: "drip exact crane fade erase voice soccer jump middle faculty online entry access stove rib wine baby stand",
            entropy: Data(fromHexEncodedString: "4329c8c928e4c7eaf373c78c4a366ba5d015ad6e3fdc111a")!
        ),
        (
            phrase: "whale energy penalty another tennis insane monster voyage member cotton layer please injury riot wrestle satoshi moral moral slogan acid sausage",
            entropy: Data(fromHexEncodedString: "f9a9428a04cdf2e9e3d7b08ac619f9533743747f95fb8fb1f72f80fb")!
        ),
        (
            phrase: "install assume ketchup talk giant bone foster flight situate math hurt border deputy grab mesh hope update dream evolve caught erupt win danger thought",
            entropy: Data(fromHexEncodedString: "7561bde7eec61a329702c7c9b121bf0ce3b4caa2f36bee8851389234cff68ddf")!
        )
    ]
    
    func testMnemonicToEntropy() throws {
        for (phrase, entropy) in testCases {
            let mnemonic = try Mnemonic.toEntropy(phrase.components(separatedBy: " "))
            XCTAssertEqual(mnemonic, Array(entropy))
        }
    }
    
    func testEntropyToMnemonic() throws {
        for (phrase, entropy) in testCases {
            let mnemonic = try Mnemonic.toMnemonic(Array(entropy))
            XCTAssertEqual(mnemonic.joined(separator: " "), phrase)
        }
    }
    
    func testSeedMnemonics() throws {
        let seed = Seed32(base58: "62Lx2E8L55xwxMUwPQdtAdTufa3x71AAh3N2WUgY2Quy")!
        let mnemonic = seed.mnemonic
        let seedResult = Seed32(mnemonic: mnemonic)!
        
        XCTAssertEqual(seed, seedResult)
        XCTAssertEqual(mnemonic.words.count, 24)
    }
    
    func testInvalidMnemonic() {
        XCTAssertThrowsError(try Mnemonic.toEntropy("sleep kitten".components(separatedBy: " ")))
        XCTAssertThrowsError(try Mnemonic.toEntropy("sleep kitten sleep kitten sleep kitten".components(separatedBy: " ")))
        XCTAssertThrowsError(try Mnemonic.toEntropy("abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about end grace oxygen maze bright face loan ticket trial leg cruel lizard bread worry reject journey perfect chef section caught neither install industry".components(separatedBy: " ")))
        XCTAssertThrowsError(try Mnemonic.toEntropy("turtle front uncle idea crush write shrug there lottery flower risky shell".components(separatedBy: " ")))
        XCTAssertThrowsError(try Mnemonic.toEntropy("sleep kitten sleep kitten sleep kitten sleep kitten sleep kitten sleep kitten".components(separatedBy: " ")))
    }
}
