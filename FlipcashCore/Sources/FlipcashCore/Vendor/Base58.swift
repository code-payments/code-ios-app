import Foundation
import SharedCoreKit

/// Base58 over the Bitcoin/Solana alphabet.
///
/// The implementation is the shared Kotlin one in `SharedCoreKit`; this type keeps the
/// call-site shape the rest of FlipcashCore already uses.
public enum Base58 {

    public static func fromBytes(_ bytes: [UInt8]) -> String {
        SharedCoreKit.Base58.encode(Data(bytes))
    }

    /// Returns `[]` for input holding a character outside the alphabet, and trims surrounding
    /// whitespace first — both behaviors the previous implementation had and callers rely on.
    public static func toBytes(_ base58: String) -> [UInt8] {
        let trimmed = base58.trimmingCharacters(in: .whitespaces)
        guard let decoded = SharedCoreKit.Base58.decode(trimmed) else { return [] }
        return [UInt8](decoded)
    }
}
