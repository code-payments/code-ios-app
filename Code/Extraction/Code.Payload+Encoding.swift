//
//  Code.Payload+Encoding.swift
//  Code
//
//  Created by Dima Bart on 2021-02-08.
//

import Foundation
import CodeServices
import CodeScanner

extension Code.Payload {
    
    static let length: Int = 20
    
    init(data: Data) throws {
        guard data.count == Code.Payload.length else {
            throw Error.invalidDataSize
        }
        
        var mutableData = data
        
        let (kind, value, nonce) = try mutableData.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) -> (Kind, Value, Data) in
            let base = buffer.baseAddress!
            
            let type = base.advanced(by: 0).assumingMemoryBound(to: UInt8.self).pointee
            
            guard let kind = Code.Payload.Kind(rawValue: type) else {
                throw Error.invalidKind
            }
            
            let value: Value
            
            switch kind {
            case .cash, .giftCard:
                let quarks = base.advanced(by: 1).assumingMemoryBound(to: UInt64.self).pointee
                value = .kin(Kin(quarks: quarks))
                
            case .requestPayment, .login, .requestPaymentV2:
                let currencyIndex = base.advanced(by: 1).assumingMemoryBound(to: UInt8.self).pointee
                
                guard let currency = CurrencyCode(index: currencyIndex) else {
                    throw Error.invalidCurrencyIndex
                }
                
                var amountData = Data(count: MemoryLayout<UInt64>.stride)
                let amountCents = amountData.withUnsafeMutableBytes {
                    let b = $0.baseAddress!
                    b.copyMemory(from: base.advanced(by: 2), byteCount: 7)
                    return b.assumingMemoryBound(to: UInt64.self).pointee
                }
                
                value = .fiat(
                    Fiat(
                        currency: currency,
                        amount: Decimal(amountCents) / 100
                    )
                )
                
            case .tip:
                
                // Skip flags at [1...4] for now, username starts at byte 5
                
                let usernameString = String(data: data[5...], encoding: .utf8)
                
                guard let usernameString else {
                    throw Error.invalidUsername
                }
                
                guard let username = usernameString.components(separatedBy: ".").first else {
                    throw Error.invalidUsername
                }
                
                return (kind, .username(username), Data())
            }
            
            var nonce = Data(count: Data.nonceLength)
            nonce.withUnsafeMutableBytes {
                $0.copyBytes(from: buffer.suffix(from: 9))
            }
            
            return (kind, value, nonce)
        }
        
        self.init(
            kind: kind,
            value: value,
            nonce: nonce
        )
    }
    
    static func encode(kind: Kind, kin: Kin, nonce: Data) -> Data {
        var data = Data(count: Code.Payload.length)
        
        data.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) in
            let base = buffer.baseAddress!
            
            var k = kind.rawValue
            base.advanced(by: 0).copyMemory(from: &k, byteCount: MemoryLayout<UInt8>.stride)
            
            var q = kin.quarks
            base.advanced(by: 1).copyMemory(from: &q, byteCount: MemoryLayout<UInt64>.stride)
            
            nonce.withUnsafeBytes { (pointer: UnsafeRawBufferPointer) in
                base.advanced(by: 9).copyMemory(from: pointer.baseAddress!, byteCount: Data.nonceLength)
            }
        }
        
        return data
    }
    
    static func encode(kind: Kind, fiat: Fiat, nonce: Data) -> Data {
        var data = Data(count: Code.Payload.length)
        
        let amount = UInt64((fiat.amount * 100).doubleValue)
        
        data.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) in
            let base = buffer.baseAddress!
            
            var k = kind.rawValue
            base.advanced(by: 0).copyMemory(from: &k, byteCount: MemoryLayout<UInt8>.stride)
            
            var c = fiat.currency.index
            base.advanced(by: 1).copyMemory(from: &c, byteCount: MemoryLayout<UInt8>.stride)
            
            var f = amount
            base.advanced(by: 2).copyMemory(from: &f, byteCount: MemoryLayout<UInt64>.stride - 1)
            
            nonce.withUnsafeBytes { (pointer: UnsafeRawBufferPointer) in
                base.advanced(by: 9).copyMemory(from: pointer.baseAddress!, byteCount: Data.nonceLength)
            }
        }
        
        return data
    }
    
    static func encode(kind: Kind, username: String) -> Data {
        var data = Data(count: Code.Payload.length)
        
        data.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) in
            let base = buffer.baseAddress!
            
            var k = kind.rawValue
            base.advanced(by: 0).copyMemory(from: &k, byteCount: MemoryLayout<UInt8>.stride)
            
            let maxLength = 15
            let sanitizedUsername = username.prefix(maxLength)
            
            let u = Data(sanitizedUsername.utf8)
            u.withUnsafeBytes { usernameBuffer in
                base.advanced(by: 5).copyMemory(from: usernameBuffer.baseAddress!.assumingMemoryBound(to: Byte.self), byteCount: sanitizedUsername.count)
            }
            
            let paddingRequired = maxLength - sanitizedUsername.count
            
            var padding: String = ""
            
            if paddingRequired > 0 {
                padding = "."
            }
            
            if paddingRequired > 1 {
                let hash = SHA256.digest(username).base64EncodedString()
                padding = "\(padding)\(hash.prefix(paddingRequired - 1))"
            }
            
            if !padding.isEmpty {
                let paddingData = Data(padding.utf8)
                paddingData.withUnsafeBytes { paddingBuffer in
                    base.advanced(by: 5 + sanitizedUsername.count).copyMemory(from: paddingBuffer.baseAddress!.assumingMemoryBound(to: Byte.self), byteCount: paddingData.count)
                }
            }
        }
        
        return data
    }
    
    func encode() -> Data {
        switch value {
        case .kin(let kin):
            return Self.encode(
                kind: kind,
                kin: kin,
                nonce: nonce
            )
            
        case .fiat(let fiat):
            return Self.encode(
                kind: kind,
                fiat: fiat,
                nonce: nonce
            )
            
        case .username(let username):
            return Self.encode(
                kind: kind,
                username: username
            )
        }
    }
    
    func codeData() -> Data {
        KikCodes.encode(encode())
    }
}

extension Code.Payload {
    enum Error: Swift.Error {
        case invalidDataSize
        case invalidKind
        case invalidCurrencyIndex
        case invalidUsername
    }
}

/*
 
 Layout 0: Cash
 
   0   1   2   3   4   5   6   7   8   9  10  11  12  13  14  15  16  17  18  19
 +---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+
 | T |            Amount             |                   Nonce                   |
 +---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+
 
 (T) Type (1 byte)

 The first byte of the data in all Code scan codes is reserved for the scan
 code type. This field indicates which type of scan code data is contained
 in the scan code. The expected format for each type is outlined below.
 
 Kin Amount in Quarks (8 bytes)

 This field indicates the number of quarks the payment is for. It should be
 represented as a 64-bit unsigned integer.

 Nonce (11 bytes)

 This field is an 11-byte randomly-generated nonce. It should be regenerated
 each time a new payment is initiated.
 
 
 
 Layout 1: Gift Card
 
 Same as layout 0.
 
 
 
 Layout 2: Payment Request
 
   0   1   2   3   4   5   6   7   8   9  10  11  12  13  14  15  16  17  18  19
 +---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+
 | T | C |        Fiat               |                   Nonce                   |
 +---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+
 
 (T) Type (1 byte)

 The first byte of the data in all Code scan codes is reserved for the scan
 code type. This field indicates which type of scan code data is contained
 in the scan code. The expected format for each type is outlined below.
 
 (C) Currency Code (1 bytes)

 This field indicates the currency code for the fiat amount. The value is an
 encoded index less than 255 that maps to a currency code in CurrencyCode.swift
 
 Fiat Amount (7 bytes)

 This field indicates the fiat amount, denominated in `Currency` above. The amount
 is an integer value calculated as follows: $5.00 x 100 = 500. The decimals are
 offset by multiplying by 100 and encoding the integer result. When decoding, the
 amount should be divided by 100 again to return the original value.

 Nonce (11 bytes)

 This field is an 11-byte randomly-generated nonce. It should be regenerated
 each time a new payment is initiated.
 
 
 
 Layout 5: Tip
 
   0   1   2   3   4   5   6   7   8   9  10  11  12  13  14  15  16  17  18  19
 +---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+
 | T |     Flags     |             username                  | ... remainder (0) |
 +---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+---+
 
 (T) Type (1 byte)

 The first byte of the data in all Code scan codes is reserved for the scan
 code type. This field indicates which type of scan code data is contained
 in the scan code.
 
 (F) Flags (4 bytes)

 Optional flags may provide additional context on the type of username embedded in
 the scan code.
 
 Username (15 bytes)

 The username that uniquely represents a user's tip code. Cannot be longer than 15
 bytes. Any additional space is represented by an empty string in (remainder).
 
 */
