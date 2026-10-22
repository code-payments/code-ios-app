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
    /// Two things make it evaluate again without touching identity, so `@State`, navigation and focus
    /// survive: handing each hosting controller its root view, which reaches views holding a closure,
    /// and bumping `HotSwapState.generation`, which invalidates every view declaring `@HotSwappable`.
    /// A view with neither keeps its old body until something else redraws it.
    fileprivate static func refresh() {
        HotSwapState.shared.generation += 1
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows {
                refresh(window.rootViewController)
            }
        }
        CATransaction.flush()
    }

    private static func refresh(_ vc: UIViewController?) {
        guard let vc else { return }
        vc.view.setNeedsLayout()
        for child in vc.children { refresh(child) }
        refresh(vc.presentedViewController)
        HotSwapHosting.invalidate(vc)
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
            await MainActor.run { HotSwap.refresh() }
            let shownMs = Int(Date().timeIntervalSince(started) * 1000)
            NSLog("hotswap: %@ applied, %d bytes, download %dms, dlopen %dms", name, data.count, downloadMs, loadMs)
            await report(["event": "patch", "seq": seq, "name": name, "ok": true, "bytes": data.count,
                          "downloadMs": downloadMs, "loadMs": loadMs, "shownMs": shownMs])
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

@MainActor
final class HotSwapState: ObservableObject {
    static let shared = HotSwapState()
    @Published var generation = 0
}

/// Declared on a view a patch may replace: `@HotSwappable private var hotSwap`. It subscribes the view
/// to each patch, so its `body` runs again in place. An `@Observable` read would not do: Observation
/// tracks only what `body` reads, and the old `body` never read it.
@MainActor @propertyWrapper
struct HotSwappable: DynamicProperty {
    @ObservedObject private var state = HotSwapState.shared
    var wrappedValue: Int { state.generation }
    init() {}
}

enum HotSwapHosting {
    @MainActor static func invalidate(_ vc: UIViewController) {
        (vc as? any HotSwapRefreshable)?.hotSwapRefresh()
    }
}

@MainActor protocol HotSwapRefreshable { func hotSwapRefresh() }

extension UIHostingController: HotSwapRefreshable {
    func hotSwapRefresh() { rootView = rootView }
}
#endif
