import Testing
import Foundation
import FlipcashUI
@testable import Flipcash

@MainActor
@Suite("GoldBarTextureStore")
struct GoldBarTextureStoreTests {

    private static let key = GoldBarTextureStore.Key(
        payload: .placeholder35, stampLines: ["$1.00"], serial: "TEST"
    )

    @Test("A repeat request returns the cached texture set (same instances)")
    func repeatRequest_hitsCache() async {
        let store = GoldBarTextureStore()
        let first = await store.textures(for: Self.key)
        let second = await store.textures(for: Self.key)
        #expect(first.albedo === second.albedo)
    }

    @Test("Concurrent requests for the same key share one bake")
    func concurrentRequests_shareBake() async {
        let store = GoldBarTextureStore()
        async let first = store.textures(for: Self.key)
        async let second = store.textures(for: Self.key)
        let (a, b) = await (first, second)
        #expect(a.albedo === b.albedo)
    }

    @Test("A different key misses the cache")
    func differentKey_missesCache() async {
        let store = GoldBarTextureStore()
        let first = await store.textures(for: Self.key)
        let other = await store.textures(for: .init(payload: .placeholder35, stampLines: ["$2.00"], serial: "TEST"))
        #expect(first.albedo !== other.albedo)
    }
}
