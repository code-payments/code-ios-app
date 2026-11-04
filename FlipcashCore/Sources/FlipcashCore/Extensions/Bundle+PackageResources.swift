import Foundation

extension Bundle {

    /// Returns the containing app's copy of the package resource bundle `name` when running in an
    /// app extension, a loaded test bundle's copy under package tests, otherwise `fallback`.
    public static func packageResources(named name: String, fallback: @autoclosure () -> Bundle) -> Bundle {
        // The appex build strips its own copy of these bundles (Scripts/strip-appex-package-resources.sh)
        // so they ship once; an appex lives at Flipcash.app/PlugIns/X.appex.
        let main = Bundle.main.bundleURL
        if main.pathExtension == "appex" {
            let app = main.deletingLastPathComponent().deletingLastPathComponent()
            if let bundle = Bundle(url: app.appendingPathComponent("\(name).bundle")) {
                return bundle
            }
        }
        // Package tests (FlipcashCoreVectors) copy the bundle into the .xctest, which the generated
        // `Bundle.module` can't reach once the product is a dynamic framework; it traps instead.
        for loaded in Bundle.allBundles where loaded.bundleURL.pathExtension == "xctest" {
            if let bundle = loaded.resourceURL.flatMap({ Bundle(url: $0.appendingPathComponent("\(name).bundle")) }) {
                return bundle
            }
        }
        return fallback()
    }

    /// FlipcashCore's resource bundle (the discrete pricing tables).
    static let flipcashCore = packageResources(named: "FlipcashCore_FlipcashCore", fallback: .module)
}
