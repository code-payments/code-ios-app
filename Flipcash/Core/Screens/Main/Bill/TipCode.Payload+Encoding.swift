//
//  TipCode.Payload+Encoding.swift
//  Flipcash
//

import Foundation
import FlipcashCore
import CodeScanner

nonisolated extension TipCode.Payload {

    /// The shared frame both code kinds are encoded into.
    static let length: Int = 20

    /// The leading byte of every tip payload.
    static let kind: UInt8 = 2

    private static let userIDRange = 1..<17

    init(data: Data) throws {
        guard !data.isEmpty, data.count <= Self.length else {
            throw Error.invalidDataSize
        }

        // `KikCodes.decode` drops trailing zero bytes, so a user id ending in
        // zeros comes back short. Restore the fixed frame before reading it.
        var bytes = Data(data)
        bytes.append(Data(count: Self.length - bytes.count))

        guard bytes[0] == Self.kind else {
            throw Error.invalidKind
        }

        // Re-base the slice: `UUID(data:)` subscripts from 0.
        self.init(userID: try UserID(data: Data(bytes[Self.userIDRange])))
    }

    func encode() -> Data {
        var data = Data(count: Self.length)
        data[0] = Self.kind
        data.replaceSubrange(Self.userIDRange, with: userID.data)
        return data
    }

    func codeData() -> Data {
        KikCodes.encode(encode())
    }
}

extension TipCode.Payload {
    enum Error: Swift.Error {
        case invalidDataSize
        case invalidKind
    }
}
