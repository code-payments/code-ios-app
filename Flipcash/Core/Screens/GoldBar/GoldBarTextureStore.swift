import UIKit
import FlipcashCore

private nonisolated let logger = Logger(label: "flipcash.gold-bar")

/// The only entry point for gold-bar texture bakes: renders the Kik code,
/// coalesces concurrent bakes (at most one in flight per key), and keeps the
/// most recent result so a re-presentation opens at full quality immediately.
@MainActor
final class GoldBarTextureStore {

    static let shared = GoldBarTextureStore()

    /// Everything that bakes into the face textures — text changes must miss the cache.
    struct Key: Equatable {
        let payload: Data
        let stampLines: [String]
        let serial: String

        /// The single derivation for a USDF bill's bar face — `showCashBill`'s
        /// preheat and the presented `GoldBarBillView` must agree on the key or
        /// the early bake is wasted.
        static func usdfBill(fiat: FiatAmount, codeData: Data) -> Key {
            Key(payload: codeData, stampLines: [fiat.formatted(suffix: nil)], serial: PublicKey.usdf.base58)
        }
    }

    private var cached: (key: Key, textures: GoldBarMaterialBaker.Textures)?
    private var inflight: (key: Key, task: Task<GoldBarMaterialBaker.Textures, Never>)?

    /// Kicks the bake for a key without waiting on it — call as soon as the
    /// bill exists (`showCashBill`), before the canvas starts presenting.
    func preheat(key: Key) {
        Task { _ = await textures(for: key) }
    }

    func textures(for key: Key) async -> GoldBarMaterialBaker.Textures {
        if let cached, cached.key == key { return cached.textures }
        if let inflight, inflight.key == key { return await inflight.task.value }

        let code = GoldBarCodeRenderer.image(for: key.payload, side: 480)
        let config = GoldBarMaterialBaker.Config.full(code: code, stampLines: key.stampLines, serial: key.serial)
        let task = Task.detached(priority: .userInitiated) {
            let clock = ContinuousClock()
            let start = clock.now
            let textures = GoldBarMaterialBaker.bake(config)
            logger.info("Baked gold bar textures", metadata: ["duration": "\(clock.now - start)"])
            return textures
        }
        inflight = (key, task)
        let textures = await task.value
        cached = (key, textures)
        if inflight?.key == key { inflight = nil }
        return textures
    }
}
