//
//  HotSwap.swift
//  Flipcash
//

#if DEBUG
import UIKit
import SwiftUI

/// Debug-only live patching. Long-polls a Mac server (`Scripts/hotswap/`) for patch dylibs, downloads each
/// into Caches and `dlopen`s it. A patch carries `@_dynamicReplacement` bodies for functions in this
/// module, which works because the Debug configuration compiles with `-enable-implicit-dynamic`.
///
/// The server is `HotSwapServer` in UserDefaults, so `-HotSwapServer http://host:port` on the launch
/// arguments sets it. The default is the Mac's Tailscale address. The whole file is compiled out of
/// Release, where the bundle id is the same, so a Release app can never fetch code.
///
/// The host must be an IP address: ATS does not apply to those, and the app's Info.plist allows no
/// other plain-HTTP load.
@MainActor
enum HotSwap {

    static let defaultServer = "http://100.91.141.96:18490"

    private static var started = false

    static var server: String {
        UserDefaults.standard.string(forKey: "HotSwapServer") ?? defaultServer
    }

    static func start() {
        guard !started, !Container.isRunningTests, !Container.isRunningUITests else { return }
        started = true
        let base = server
        Task.detached(priority: .utility) { await Poller(base: base).run() }
    }

    /// Called after a patch loads, on the main actor. A replaced `body` only takes effect when SwiftUI
    /// next evaluates it, and SwiftUI skips a view whose stored properties compare equal to last time.
    /// So each hosting view's AttributeGraph is told that every value in it is out of date, which makes
    /// every `body` run again without touching identity: `@State`, navigation, focus and scroll survive,
    /// and no view has to declare anything. Returns `graph` when that ran on every hosting view, or
    /// `fallback` when a graph or the symbol was not found and only the root views were handed back,
    /// which reaches views holding a closure and no others.
    @discardableResult
    fileprivate static func refresh() -> String {
        var redraw = HotSwapGraph.available ? "graph" : "fallback"
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows {
                refresh(window.rootViewController, &redraw)
            }
        }
        CATransaction.flush()
        return redraw
    }

    private static func refresh(_ vc: UIViewController?, _ redraw: inout String) {
        guard let vc else { return }
        vc.view.setNeedsLayout()
        for child in vc.children { refresh(child, &redraw) }
        refresh(vc.presentedViewController, &redraw)
        if let host = vc as? any HotSwapRefreshable {
            if !HotSwapGraph.invalidate(vc.view) { redraw = "fallback" }
            host.hotSwapRefresh()
        }
    }

    private final class Poller: @unchecked Sendable {
        let base: String
        let dir: URL

        init(base: String) {
            self.base = base
            dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("hotswap", isDirectory: true)
            try? FileManager.default.removeItem(at: dir)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        func run() async {
            NSLog("hotswap: polling %@", base)
            await report(["event": "baseline", "bundle": Bundle.main.bundleIdentifier ?? ""])
            var seq = 0
            while true {
                guard let url = URL(string: base + "/next?after=\(seq)") else { return }
                var req = URLRequest(url: url)
                req.timeoutInterval = 40
                let data: Data, resp: URLResponse
                do { (data, resp) = try await URLSession.shared.data(for: req) } catch {
                    if (error as? URLError)?.code != .timedOut { NSLog("hotswap: poll failed: %@", "\(error)") }
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    continue
                }
                guard (resp as? HTTPURLResponse)?.statusCode == 200,
                      let notice = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let next = notice["seq"] as? Int, let name = notice["name"] as? String else { continue }
                seq = next
                await apply(name, seq: seq)
            }
        }

        private func apply(_ name: String, seq: Int) async {
            let started = Date()
            guard let url = URL(string: base + "/patches/" + name),
                  let (data, resp) = try? await URLSession.shared.data(from: url),
                  (resp as? HTTPURLResponse)?.statusCode == 200 else {
                await report(["event": "patch", "seq": seq, "name": name, "ok": false, "error": "download failed"])
                return
            }
            let downloadMs = Int(Date().timeIntervalSince(started) * 1000)
            let dest = dir.appendingPathComponent(name)
            do { try data.write(to: dest) } catch {
                await report(["event": "patch", "seq": seq, "name": name, "ok": false, "error": "write: \(error)"])
                return
            }
            let t0 = Date()
            guard dlopen(dest.path, RTLD_NOW | RTLD_GLOBAL) != nil else {
                let err = String(cString: dlerror())
                NSLog("hotswap: %@ refused: %@", name, err)
                await report(["event": "patch", "seq": seq, "name": name, "ok": false, "error": err])
                return
            }
            let loadMs = Int(Date().timeIntervalSince(t0) * 1000)
            let redraw = await MainActor.run { HotSwap.refresh() }
            let shownMs = Int(Date().timeIntervalSince(started) * 1000)
            NSLog("hotswap: %@ applied, %d bytes, download %dms, dlopen %dms", name, data.count, downloadMs, loadMs)
            await report(["event": "patch", "seq": seq, "name": name, "ok": true, "bytes": data.count,
                          "downloadMs": downloadMs, "loadMs": loadMs, "shownMs": shownMs, "redraw": redraw])
        }

        private func report(_ fields: [String: Any]) async {
            guard let url = URL(string: base + "/report") else { return }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.httpBody = try? JSONSerialization.data(withJSONObject: fields)
            _ = try? await URLSession.shared.data(for: req)
        }
    }
}

/// SwiftUI's private AttributeGraph, reached from a `_UIHostingView`. Nothing here is API: the path
/// `_base.viewGraph.viewGraph` comes from `Mirror` on iOS 27.0, and `ViewGraph` keeps its graph in a
/// field `Mirror` does not show, so it is found by scanning the object's first words for a CF object
/// whose type is `AGGraph`. Every step that misses returns false, and `refresh` falls back.
enum HotSwapGraph {
    private typealias TypeIDFn = @convention(c) () -> UInt
    private typealias GraphFn = @convention(c) (UnsafeRawPointer) -> Void

    private static let symbols: (typeID: UInt, invalidateAll: GraphFn)? = {
        let rtld = UnsafeMutableRawPointer(bitPattern: -2) // RTLD_DEFAULT
        guard let t = dlsym(rtld, "AGGraphGetTypeID"), let i = dlsym(rtld, "AGGraphInvalidateAllValues") else {
            NSLog("hotswap: AttributeGraph symbols not found; patched views redraw only through their root")
            return nil
        }
        return (unsafeBitCast(t, to: TypeIDFn.self)(), unsafeBitCast(i, to: GraphFn.self))
    }()

    static var available: Bool { symbols != nil }

    @MainActor static func invalidate(_ view: UIView) -> Bool {
        guard let symbols,
              let base = Mirror(reflecting: view).descendant("_base"),
              let host = Mirror(reflecting: base).descendant("viewGraph"),
              let graph = Mirror(reflecting: host).descendant("viewGraph"),
              type(of: graph) is AnyClass else { return false }
        let found = graphs(in: graph as AnyObject, typeID: symbols.typeID)
        for g in found { symbols.invalidateAll(g) }
        return !found.isEmpty
    }

    private static func graphs(in object: AnyObject, typeID: UInt) -> [UnsafeRawPointer] {
        let base = Unmanaged.passUnretained(object).toOpaque()
        var out: [UnsafeRawPointer] = []
        for offset in stride(from: 16, to: 160, by: 8) {
            let word = base.load(fromByteOffset: offset, as: UInt.self)
            guard word > 0x1_0000_0000, word & 7 == 0,
                  let p = UnsafeRawPointer(bitPattern: word), malloc_size(p) > 0 else { continue }
            // A Swift-native object has no CF type; asking it for one is an unrecognised selector.
            guard Unmanaged<AnyObject>.fromOpaque(p).takeUnretainedValue() is NSObject else { continue }
            if CFGetTypeID(Unmanaged<CFTypeRef>.fromOpaque(p).takeUnretainedValue()) == typeID { out.append(p) }
        }
        return out
    }
}

@MainActor protocol HotSwapRefreshable { func hotSwapRefresh() }

extension UIHostingController: HotSwapRefreshable {
    func hotSwapRefresh() { rootView = rootView }
}
#endif
