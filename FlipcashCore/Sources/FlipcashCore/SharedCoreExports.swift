// Re-exported so the app target can name the shared vocabulary -- `ReportReason` and
// `ReportDescription` -- through `import FlipcashCore`, the way it already reaches `Logging`.
//
// The app target must NOT depend on `SharedCoreKit` directly: adding it to an Xcode target's
// package dependencies gives the package a second identity, and the build fails with
// `multiple similar targets 'SharedCore', 'SharedCoreKit'`. See FlipcashCore/Package.swift.
@_exported import SharedCoreKit
