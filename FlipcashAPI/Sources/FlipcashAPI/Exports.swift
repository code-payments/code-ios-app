// FlipcashAPI is an umbrella over the two published contract packages.
//
// The generated code used to live here, vendored alongside a copy of the .proto files. It now
// ships from code-payments/ocp-client-protocol and code-payments/flipcash2-client-protocol,
// which generate from the same upstream contracts this package used to pull with
// Scripts/pull_protos.
//
// Re-exporting rather than asking callers to import the two modules directly keeps `import
// FlipcashAPI` working unchanged, which is what every consumer in this repo already writes.

@_exported import OCPClientProtocol
@_exported import Flipcash2ClientProtocol
