//
//  MerkleProofTests.swift
//  CodeServicesTests
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import XCTest
@testable import CodeServices

class MerkleProofServerTests: XCTestCase {
    
    private let root  = Hash(Data(fromHexEncodedString: "1d92df473ed3fd6326f7ee570ec34547a42a487a7500366ee8ce3bd2e3f5c99c")!)!
    private let proof = [
        "d103cfb5e499c566904787533afbdec56f95492d67fc00e2c0d0161ba99653f1",
        "1fe3bed0007741bcb18e6a55d0a1b4742182c2a8a4ca67fe39c8d2f34492d02c",
        "858921767bcad0ecb97bab67588a0c0a3e07098c68918fb47f1cd389ceb532a5",
        "689311a4b926352c5abd99b68ad505a8bc52b9d38a8e8222a69fe31743459e84",
        "349384c18d4631d050d1e6654566f368b03fab67e19e91bf564ee449e70679af",
        "0081045413c64a2bceef711c88c83a474dd45281a5c3802cb19c64297ee2abcd",
        "0d55a20d88a8a3b6ec1bdc0a2917ab8bd6073e2c6b4b7fbe150099bbb9e3cd08",
        "696f022c109b9e4d517b46211d122588a3c8a8484c16fa9ce85b8adf042fbe20",
        "5162aaf0959532c29243ed986e7db0b670efe182a3a233859c50d160333a0e64",
        "c217e4ae5aba97363aae942bc514b73fb3ec3b568ba7502755538ae244c05438",
        "07c3d35566546b2515053df639707588ac3170ed3b14cc46c4db0651a6160542",
        "f4bc1133f8c2cb9cd9e08cabfe06c16ee60a03b832401d4c02c587c22bd2e9f4",
        "1a17b1e27114c2f1f16fa898557ed0f8546e00cf9cc1dd8a07781d8bafbadba5",
        "18ea423c80045847f939c0e57c6d6255d4cc7ed4c72f2c5528cc122fac687733",
        "cd097bb2b70eabc6538d44d1583c0f2712b5a6ff16d3d7f9c22455cf0d786f47",
        "be2ff6be7e99eca6736741b87cb131950f14496bd4eb8061a17a95f45b6fd9e8",
    ].map { Hash(Data(fromHexEncodedString: $0)!)! }
    
    func testValidProof() {
        let originalCommitment = Data("leaf0".utf8)
        XCTAssertTrue(originalCommitment.verifyContained(in: root, using: proof))
    }
    
    func testInvalidCommitment() {
        let originalCommitment = Data("leaf1".utf8)
        XCTAssertFalse(originalCommitment.verifyContained(in: root, using: proof))
    }
    
    func testSingleInvalidNode() {
        let originalCommitment = Data("leaf0".utf8)
        
        for (index, _) in proof.enumerated() {
            var modifiedProof = proof
            
            var nodeBytes = modifiedProof[index].bytes
            nodeBytes[31] = 0xFF // Modify the last byte of every node
            modifiedProof[index] = Hash(nodeBytes)!
            
            XCTAssertFalse(originalCommitment.verifyContained(in: root, using: modifiedProof))
        }
    }
}

class MerkleProofClientTests: XCTestCase {
    
    private let leaf = PublicKey(base58: "2ocuvgy8ETZp9WDaEy4rpYz2QyeZ7JAiEvXKbW5rKcd4")!
    private let root = Hash(base58: "9EuLAJgnMpEq8wmQUFTNxgYJG2FkAPAGCUhrNK447Uox")!
    private let proof = [
        "4DEt3CHLarXBy74hiJf5t74HmKfTw5DeLK2nzTLFv3Pq",
        "73uNXKLpHkTgc9ubvyRXTGaNUh19TUx8M9bN4PNTn544",
        "2QH34Bqm89sadRqpz1U5M3Cd34xxNLnTHdxzn4LA3EKU",
        "AaySpzaCsgyTVVgUA9bNTNC6sGsws7sTYNyz2oFAe1gT",
        "BFHDwqjAPupY4PoJn5Lvx7t9mQrXy6iGnTS7NuRyrEav",
        "BFy4XgE4j8NW5PxzDMkH7FWXZcMuFb9zoVSBqdjxm21A",
        "B5Lvj9Zdrynu2DGjYXGmxKxRbvmVFtYoGLyqrzZFymXo",
        "GEspB8aMfyV4Hmtt7fGmFXsZ5QWrbBUSfPeDT3dXS7gG",
        "FuVPGmTwWZayoWt4th2dv8X9xEmRrLvqTbdAXXfRi6Ei",
        "CbTZ7BrcBUsmGEjUqxrjkvDkKNRRJHrjF9tTb3mLmMWb",
        "GEoigbUN6rsrrpRdNi5rJgX2YDXmE6gDsLYevSchzcg4",
        "Gb2zXSV9vxhPkem6PrW45rPiEy9dbJ9nFg7ixQEV4JYh",
        "Bb2r8JJdExSAasR38yuTJu2XHRZEGHRxCR71MrJ6nW1z",
        "5zTGsTA9vmzGYwVYeD3MDcehybca93prZRdjVqRzZQ6y",
        "BbH8JeD3emXYkNw3DvLERM3hMPXhgCEqcU132hSo2uH7",
        "F9re8k2sX2BVGX8WqRBGyiZ2aPvvRj4s62jmtgM73hmT",
        "DGFU6XD6eYi3GtVAwYBP4d2DUYv1BGiquijQH6HXLLi4",
        "8TaNzgiEAP4VoXkBjb1toiZ9fw84RhqezdYt3RhNXR3u",
        "BnF8qb2kYZxFHtmqWircb1Di33XTQc8TV17oFwi1tZ4u",
        "BBNfGrQ7cKBcZgQmqCgw45s9QLkx41qcTjYwrn7tAtoM",
        "Dkf4Fpukx558idi6XwnEx9aAu8GLDzYUC3eN7hQQxPsJ",
        "72BxCoqc9cnQvqEZmqzLcZH7VyMBjJFj3R47D8gpV8WL",
        "BSVw2t3RwN4ab9Zpd68pwLqwHVecgHvacZB28QgNQ3L",
        "7YvGe21SSF93mZoyPsgVF6dD78YWCkVwSff9a4EdE3aj",
        "9wZwjy3V8827XZeeE4CxZgXU5WsRGCfcRYHkaPtB7QGb",
        "GQb7NMsiEfwVWxuLgn7Tev1KEZSs4ASayUiULjACtxNv",
        "Wpb4nF5rc9GpSbWXPUNwA31bemJp61HexerhUx97H8B",
        "HwXMPKHXQoBQkM533yqatDbaY3HLDapUWVGVWUv6366a",
        "Wom44oATBqSD7SZpBwHRmkXhKV4qsC7SnneGTLKhvdN",
        "3xmn2hQdDSKN1ompFNh6AwnQBucWK7Z8mJPyXJzTpLb4",
        "HQ5WDTtCvL14aa16UZJStZVVCTcoYbiUayzzBFm8e97r",
        "Af6F2xzEKyjuiy7wjukatK9BzW42K7vXekkZq9C7W3K",
        "ECS1Mcvt2pYJxYkMDNAp4sNjQq4SadsL3KeJx59ATLbo",
        "5B2C3uLH4TvrrriZgo5UbfQwDVbeqqtd7NPwaujfipAd",
        "DLd8jX9r1o57SaBgnqzextfBHb7aSGdL98t3EzhiKXjC",
        "2cz8R5HYZXs5PKhXXXr562go49A4d5gor42Khejz8K2A",
        "B8ucJEMrosxPoSnnBgMbkcmsGWoqusaaheATT8UFa7AF",
        "D7JCQL3FMGkoqfvvP9TBzzirTeNQDHbUYAxA9Di6pkQm",
        "7fiWLao84havAULW9y5mRDpAqCDSFp2hRmDfN7xQWdWk",
        "9SCyBETC2xV1yk44voyQ7MED4SSURpNsuu6MNY12KndN",
        "FQKnR4ngeSet5UfWyzXsf7RFU4QN83T9C5xSJWcHcZVX",
        "DzN3txNccgTDG58PWfgkx9wBuVPShTp1VTrPyHkvnbpq",
        "4cCa2Zen5gn83AJmAgn3mZE3NodVaYaMZM4UykQcTXyy",
        "7XDMh3UsVHVomz4MmsSPcKtEkSwxGA4S5ypUb5t2Dvmv",
        "6VoqDc2CWeg158GDuQTeerh1VWHRFbcjrKo2VeiiXAD7",
        "5uGA5QbthCBe5QiY3BwaqfnwwfJgVahZc8WHPFXwBV2m",
        "AAV7TTewgfmN6FHW3oV3ad3Q6KKcdbP6ijt7SUThD2bN",
        "AD2GHkMgEmtRFWi6HLpZeHKAeRAZUnGPF7h4mVbeUj7o",
        "By3ScwWYWdZAcFXo6V68cRH6kSbdqtUMgNVdnSNevgb5",
        "C2RCxm7ZSd9A2fXEvJguBYNK6oUdVrMSCHB3k2JxBKek",
        "FHvwmz1bJqm6SfeBLriNhSh8wuwEJc4KDxi2PpVfQtqg",
        "R29HU9mCjih74wRWLbW3nXLcUAbEJAqKUrpXENSbziS",
        "AvNJa3vqawjfrGmqKPybWQa4V42uyiigUgchT4gHt5Gf",
        "CozYPv4cdVeRb5QWCrtuVJk3f2rHJeAFD9ZtQjHLqyyW",
        "BeLz3Yqv2ikvQkmH2mxXYGHgvo93Ns77hStxSjuA8UsZ",
        "H4tEGNHHcCLbA963wtzJxsZVuEdrpQwrBBnmWcBAhChs",
        "CUmSAsfdvnJTUkWLA8chums2ffyveiRNkNVu3t6as6N7",
        "62djLqbyFJz3iJiY4NkWvio46dMfP291cWfZ44wdeDgE",
        "4JjYv9v3z2YoBrMCsmXE6abpm5bNTKwuJp99rjoTdmPF",
        "JB7wk6DDiYKjzasvHPpySd2aCjh1UX5adD5eZgazwEUM",
        "3fCTfZwwMipFUpvbXbcDBBtwuo23hmuTJMYaVECWwNTP",
        "CZ94cA7JHBb4a8mqN9xEJquPNX1TxKqL3cBQms6yfgTr",
        "8PxPosHkG5Q6VBnhiimJaH88yPYt6ZDp4szMBfaVTLun",
    ].map { PublicKey(base58: $0)! }
    
    func testValidProof() {
        XCTAssertTrue(leaf.verifyContained(in: root, using: proof))
    }
    
    func testInvalidProof() {
        var modifiedBytes = leaf.bytes
        modifiedBytes[31] = 0xFF
        let modifiedLeaf  = PublicKey(modifiedBytes)!
        
        XCTAssertFalse(modifiedLeaf.verifyContained(in: root, using: proof))
    }
    
    func testSingleInvalidNode() {
        for (index, _) in proof.enumerated() {
            var modifiedProof = proof
            
            var nodeBytes = modifiedProof[index].bytes
            nodeBytes[31] = 0xFF // Modify the last byte of every node
            modifiedProof[index] = Hash(nodeBytes)!
            
            XCTAssertFalse(leaf.verifyContained(in: root, using: modifiedProof))
        }
    }
}
