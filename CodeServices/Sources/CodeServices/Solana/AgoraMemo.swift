//
//  AgoraMemo.swift
//  CodeServices
//
//  Created by Dima Bart.
//  Copyright © 2021 Code Inc. All rights reserved.
//

import Foundation

/**
 * A memo format understood by the Agora services.
 * @param magicByteIndicator    2 bits   | less than 4
 * @param version               3 bits   | less than 8
 * @param typeId                5 bits   | less than 32
 * @param appIdx                16 bits  | less than 65,536
 * @param foreignKey            230 bits | Base64 Encoded String of [230 bits + (2 zeros padding)]
*/
public struct AgoraMemo {
    
    public let magicByte: MagicByte
    public let version: Byte
    public let transferType: TransferType
    public let appIndex: UInt16
    public let bytes: [Byte]
    
    // MARK: - Init -

    public init(magicByte: MagicByte = .default, version: Byte = 1, transferType: TransferType, appIndex: UInt16, bytes: [Byte] = []) {
        self.magicByte    = magicByte
        self.version      = version
        self.transferType = transferType
        self.appIndex     = appIndex
        
        var container = [Byte].zeroed(with: Constants.byteLength)
        _ = container.withUnsafeMutableBytes {
            bytes.copyBytes(to: $0, count: min(bytes.count, Constants.byteLength))
        }
        
        self.bytes = container
    }
}

// MARK: - Encoding -

extension AgoraMemo {

    public init(data: Data) throws {
        guard let content = Data(base64Encoded: data) else {
            throw Error.invalidData
        }
        
        var header: Int = 0
        _ = withUnsafeMutableBytes(of: &header) {
            content.copyBytes(to: $0, count: 4)
        }

        let byte         = (header & Constants.magicByteMask) >> 0
        let version      = (header & Constants.versionMask) >> 2
        let transferType = (header & Constants.transferTypeMask) >> 5
        let appIndex     = (header & Constants.appIndexMask) >> 10
        
        guard let magicByte = MagicByte(rawValue: byte) else {
            throw Error.invalidMagicByte
        }
        
        guard let transferType = TransferType(rawValue: transferType), transferType != TransferType.unknown else {
            throw Error.invalidTransferType
        }

        var bytes = [Byte].zeroed(with: Constants.byteLength)
        
        for i in 0..<Constants.byteLength {
            bytes[i] = bytes[i] | (content[i + 3] >> 2) & 0x3F
            bytes[i] = bytes[i] | ((content[i + 4] & 0x3) << 6)
        }
        
        self.init(
            magicByte: magicByte,
            version: Byte(version),
            transferType: transferType,
            appIndex: UInt16(appIndex),
            bytes: bytes
        )
    }

    /**
     * Fields below are packed from LSB to MSB order:
     * magicByteIndicator             2 bits | less than 4
     * version                        3 bits | less than 8
     * typeId                         5 bits | less than 32
     * appIdx                        16 bits | less than 65,536
     * foreignKey                   230 bits | Often a SHA-224 of an [InvoiceList] but could be anything
     */
    public func encode() -> Data {

        var result = [Byte].zeroed(with: Constants.totalByteCount)

        result[0] = magicByte.rawValue
        result[0] |= version << 2
        result[0] |= (transferType.rawValue & 0x7) << 5

        result[1] = (transferType.rawValue & 0x1c) >> 2
        result[1] |= Byte(appIndex & 0x3f) << 2

        result[2] = Byte((appIndex & 0x3fc0) >> 6)

        result[3] = Byte((appIndex & 0xc000) >> 14)

        // Encode foreign key
        result[3] |= (bytes[0] & 0x3f) << 2

        // Insert the rest of the fk. since each loop references fk[n] and fk[n + 1], the upper bound is offset by 3 instead of 4.
        for i in 4..<3 + bytes.count {
            // apply last 2-bits of current byte
            // apply first 6-bits of next byte
            result[i]  = (bytes[i - 4] >> 6) & 0x3
            result[i] |= (bytes[i - 3] & 0x3f) << 2
        }

        // If the foreign key is less than 29 bytes, the last 2 bits of the FK can be included in the memo
        if bytes.count < 29 {
            result[bytes.count + 3] = (bytes[bytes.count - 1] >> 6) & 0x3
        }

        return Data(result).base64EncodedData()
    }
}

// MARK: - Error -

extension AgoraMemo {
    public enum Error: Swift.Error {
        case invalidData
        case invalidMagicByte
        case invalidVersion
        case invalidTransferType
        case invalidAppIndex
    }
}

// MARK: - MagicByte -

extension AgoraMemo {
    public struct MagicByte: RawRepresentable, Equatable {
        
        public static let `default` = MagicByte(rawValue: 1)!
        
        public var rawValue: Byte
        
        public init?(rawValue: Int) {
            self.init(rawValue: Byte(rawValue))
        }
        
        public init?(rawValue: Byte) {
            guard rawValue > 0 && rawValue < Constants.maxMagicByteIndicatorSize else {
                return nil
            }
            
            self.rawValue = rawValue
        }
    }
}

// MARK: - TransferType -

extension AgoraMemo {
    public enum TransferType: Byte, Equatable {
        
        /// An unclassified transfer of Kin.
        case unknown
        
        /// When none of the other types are appropriate for the use case.
        case none
        
        /// Use when transferring Kin to a user for some performed action.
        case earn
        
        /// Use when transferring Kin due to purchasing something.
        case spend
        
        /// Use when transferring Kin where it does not constitute an `earn` or `spend`.
        case p2p
        
        public var rawValue: Byte {
            switch self {
            case .unknown: return .max
            case .none:    return 0
            case .earn:    return 1
            case .spend:   return 2
            case .p2p:     return 3
            }
        }
        
        public init?(rawValue: Int) {
            self.init(rawValue: Byte(rawValue))
        }

        public init?(rawValue: Byte) {
            switch rawValue {
            case 0: self = .none
            case 1: self = .earn
            case 2: self = .spend
            case 3: self = .p2p
            default:
                self = .unknown
            }
        }
    }
}

// MARK: - Constants -

private enum Constants {
    static let magicByteBitLength: Int          = 2
    static let versionBitLength: Int            = 3
    static let transferTypeBitLength: Int       = 5
    static let appIndexBitLength: Int           = 16
    static let foreignKeyBitLength: Int         = 230

    static let maxMagicByteIndicatorSize: Int   = 1 << magicByteBitLength

    static let byteLength: Int                  = foreignKeyBitLength / 8

    static let magicByteMask: Int               = 0x3
    static let versionMask: Int                 = 0x1C
    static let transferTypeMask: Int            = 0x3E0
    static let appIndexMask: Int                = 0x3FFFC00

    static let magicByteIndicatorBitOffset: Int = 0

    static let totalLowerByteCount: Int         = (magicByteBitLength + versionBitLength + transferTypeBitLength + appIndexBitLength) / 8
    static let totalByteCount: Int              = (magicByteBitLength + versionBitLength + transferTypeBitLength + appIndexBitLength + foreignKeyBitLength) / 8
}
