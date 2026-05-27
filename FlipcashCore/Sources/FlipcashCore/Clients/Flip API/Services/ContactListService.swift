//
//  ContactListService.swift
//  FlipcashCore
//

import Foundation
import FlipcashAPI
import GRPC

private let logger = Logger(label: "flipcash.contact-list-service")

final class ContactListService: CodeService<Flipcash_Contact_V1_ContactListNIOClient> {

    // MARK: - CheckSync (unary) -

    func checkSync(
        checksum: Data,
        owner: KeyPair,
        completion: @Sendable @escaping (Result<CheckSyncResult, ErrorContactSync>) -> Void
    ) {
        logger.info("Checking contact sync state")

        let request = Flipcash_Contact_V1_CheckSyncRequest.with {
            $0.clientChecksum = .with { $0.value = checksum }
            $0.auth = owner.authFor(message: $0)
        }

        let call = service.checkSync(request)
        call.handle(on: queue) { response in
            switch response.result {
            case .ok:
                completion(.success(.ok))
            case .outOfSync:
                completion(.success(.outOfSync(serverChecksum: response.serverChecksum.value)))
            case .denied:
                logger.warning("CheckSync denied")
                completion(.failure(.denied))
            case .UNRECOGNIZED(let raw):
                logger.warning("CheckSync unknown result", metadata: ["raw": "\(raw)"])
                completion(.failure(.unknown))
            }
        } failure: { _ in
            completion(.failure(.networkError))
        }
    }

    // MARK: - DeltaUpload (unary) -

    func deltaUpload(
        adds: [String],
        removes: [String],
        oldChecksum: Data,
        newChecksum: Data,
        owner: KeyPair,
        completion: @Sendable @escaping (Result<DeltaUploadResult, ErrorContactSync>) -> Void
    ) {
        logger.info("Uploading contact delta", metadata: [
            "adds": "\(adds.count)",
            "removes": "\(removes.count)"
        ])

        let request = Flipcash_Contact_V1_DeltaUploadRequest.with {
            $0.adds = adds.map { e164 in
                Flipcash_Phone_V1_PhoneNumber.with { $0.value = e164 }
            }
            $0.removes = removes.map { e164 in
                Flipcash_Phone_V1_PhoneNumber.with { $0.value = e164 }
            }
            $0.oldChecksum = .with { $0.value = oldChecksum }
            $0.newChecksum = .with { $0.value = newChecksum }
            $0.auth = owner.authFor(message: $0)
        }

        let call = service.deltaUpload(request)
        call.handle(on: queue) { response in
            switch response.result {
            case .ok:
                logger.info("Contact delta upload accepted")
                completion(.success(.ok))
            case .checksumDrift:
                logger.warning("Contact delta upload reported checksum drift")
                completion(.success(.checksumDrift))
            case .denied:
                logger.warning("DeltaUpload denied")
                completion(.failure(.denied))
            case .checksumMismatch:
                logger.error("DeltaUpload checksum mismatch — client computed wrong new_checksum")
                completion(.failure(.checksumMismatch))
            case .tooManyContacts:
                logger.warning("DeltaUpload rejected — too many contacts")
                completion(.failure(.tooManyContacts))
            case .UNRECOGNIZED(let raw):
                logger.warning("DeltaUpload unknown result", metadata: ["raw": "\(raw)"])
                completion(.failure(.unknown))
            }
        } failure: { _ in
            completion(.failure(.networkError))
        }
    }

    // MARK: - FullUpload (client-streaming) -

    /// Replace the server's stored contact set with `phones`. Chunked into
    /// requests of up to 1000 phones each per the proto's per-message cap.
    /// `expectedChecksum` is sent on every chunk — the proto declares it
    /// `required = true` per request and PGV validates per stream message.
    func fullUpload(
        phones: [String],
        checksum: Data,
        owner: KeyPair,
        completion: @Sendable @escaping (Result<Void, ErrorContactSync>) -> Void
    ) {
        logger.info("Starting full contact upload", metadata: ["count": "\(phones.count)"])

        let call = service.fullUpload(callOptions: .streaming)

        let chunks = phones.chunked(into: Self.batchSize)
        let allChunks = chunks.isEmpty ? [[]] : chunks

        for chunk in allChunks {
            let request = Flipcash_Contact_V1_FullUploadRequest.with {
                $0.phones = chunk.map { e164 in
                    Flipcash_Phone_V1_PhoneNumber.with { $0.value = e164 }
                }
                $0.expectedChecksum = .with { $0.value = checksum }
                $0.auth = owner.authFor(message: $0)
            }
            _ = call.sendMessage(request)
        }

        call.sendEnd(promise: nil)

        call.response.whenCompleteBlocking(onto: queue) { result in
            switch result {
            case .success(let response):
                switch response.result {
                case .ok:
                    logger.info("Full contact upload succeeded")
                    completion(.success(()))
                case .denied:
                    logger.warning("FullUpload denied")
                    completion(.failure(.denied))
                case .checksumMismatch:
                    logger.error("FullUpload checksum mismatch")
                    completion(.failure(.checksumMismatch))
                case .tooManyContacts:
                    logger.warning("FullUpload rejected — too many contacts")
                    completion(.failure(.tooManyContacts))
                case .UNRECOGNIZED(let raw):
                    logger.warning("FullUpload unknown result", metadata: ["raw": "\(raw)"])
                    completion(.failure(.unknown))
                }
            case .failure(let error):
                logger.error("FullUpload network error", metadata: ["error": "\(error)"])
                completion(.failure(.networkError))
            }
        }
    }

    // MARK: - GetFlipcashContacts (server-streaming) -

    /// Streams the server's currently-matched contact set. Each `onResponse`
    /// invocation delivers up to 1000 phones (per proto cap); `onCompletion`
    /// fires exactly once. Both deliver on the service's `queue`, so per-stream
    /// ordering is preserved.
    @discardableResult
    func getFlipcashContacts(
        checksum: Data,
        owner: KeyPair,
        onResponse: @Sendable @escaping (FlipcashContactsBatch) -> Void,
        onCompletion: @Sendable @escaping (Result<Void, ErrorContactSync>) -> Void
    ) -> ContactsStreamCancellation {
        logger.info("Opening Flipcash contacts stream")

        let request = Flipcash_Contact_V1_GetFlipcashContactsRequest.with {
            $0.checksum = .with { $0.value = checksum }
            $0.auth = owner.authFor(message: $0)
        }

        let streamReference = StreamReference<
            Flipcash_Contact_V1_GetFlipcashContactsRequest,
            Flipcash_Contact_V1_GetFlipcashContactsResponse
        >()

        let queue = self.queue
        let stream = service.getFlipcashContacts(request, callOptions: .streaming) { @Sendable response in
            // Emit raw E.164 strings — server-validated against the proto regex —
            // rather than routing through `Phone(_:)`. Going through
            // `PhoneNumberKit` would silently drop any string it can't parse,
            // decoupling the local matched-set from the server's truth.
            let e164s = response.contacts.map { $0.phone.value }
            let batch = FlipcashContactsBatch(
                result: FlipcashContactsBatch.Result(response.result),
                phones: e164s
            )
            queue.async { onResponse(batch) }
        }

        streamReference.stream = stream

        stream.status.whenCompleteBlocking(onto: queue) { result in
            switch result {
            case .success(let status) where status.code == .ok:
                logger.info("Flipcash contacts stream completed")
                onCompletion(.success(()))
            case .success(let status):
                logger.warning("Flipcash contacts stream closed with non-OK status", metadata: [
                    "code": "\(status.code)"
                ])
                onCompletion(.failure(.networkError))
            case .failure(let error):
                logger.error("Flipcash contacts stream network error", metadata: ["error": "\(error)"])
                onCompletion(.failure(.networkError))
            }
        }

        return ContactsStreamCancellation(streamReference)
    }

    // MARK: - Helpers -

    private static let batchSize = 1000
}

// MARK: - Result Types -

public enum CheckSyncResult: Equatable, Sendable {
    case ok
    case outOfSync(serverChecksum: Data)
}

public enum DeltaUploadResult: Equatable, Sendable {
    /// The delta was applied. Persist `newChecksum` as the next call's
    /// `oldChecksum`.
    case ok
    /// The server's stored checksum matched neither `oldChecksum` nor
    /// `newChecksum`. Caller should fall back to `fullUpload`.
    case checksumDrift
}

public struct FlipcashContactsBatch: Equatable, Sendable {
    public enum Result: Equatable, Sendable {
        case ok
        case denied
        case notFound
        case checksumDrift
        case unknown
    }

    public let result: Result
    public let phones: [String]
}

extension FlipcashContactsBatch.Result {
    init(_ proto: Flipcash_Contact_V1_GetFlipcashContactsResponse.Result) {
        switch proto {
        case .ok: self = .ok
        case .denied: self = .denied
        case .notFound: self = .notFound
        case .checksumDrift: self = .checksumDrift
        case .UNRECOGNIZED: self = .unknown
        }
    }
}

/// Sendable handle for cancelling a `getFlipcashContacts` stream.
public final class ContactsStreamCancellation: @unchecked Sendable {
    private let reference: AnyObject
    private let _cancel: () -> Void

    init<Request, Response>(_ reference: StreamReference<Request, Response>) {
        self.reference = reference
        self._cancel = { reference.cancel() }
    }

    public func cancel() { _cancel() }
}

// MARK: - Errors -

public enum ErrorContactSync: Int, Error {
    case ok = 0
    case denied = 1
    case checksumMismatch = 2
    case tooManyContacts = 3
    case notFound = 4
    case checksumDrift = 5
    case networkError = -2
    case unknown = -1
}

extension ErrorContactSync: ServerError {
    public var isReportable: Bool {
        switch self {
        case .ok, .denied, .tooManyContacts, .checksumDrift, .networkError: false
        case .checksumMismatch, .notFound, .unknown: true
        }
    }
}

// MARK: - Interceptors -

extension InterceptorFactory: Flipcash_Contact_V1_ContactListClientInterceptorFactoryProtocol {
    func makeCheckSyncInterceptors() -> [GRPC.ClientInterceptor<Flipcash_Contact_V1_CheckSyncRequest, Flipcash_Contact_V1_CheckSyncResponse>] {
        makeInterceptors()
    }

    func makeDeltaUploadInterceptors() -> [GRPC.ClientInterceptor<Flipcash_Contact_V1_DeltaUploadRequest, Flipcash_Contact_V1_DeltaUploadResponse>] {
        makeInterceptors()
    }

    func makeFullUploadInterceptors() -> [GRPC.ClientInterceptor<Flipcash_Contact_V1_FullUploadRequest, Flipcash_Contact_V1_FullUploadResponse>] {
        makeInterceptors()
    }

    func makeGetFlipcashContactsInterceptors() -> [GRPC.ClientInterceptor<Flipcash_Contact_V1_GetFlipcashContactsRequest, Flipcash_Contact_V1_GetFlipcashContactsResponse>] {
        makeInterceptors()
    }
}

// MARK: - GRPCClientType -

extension Flipcash_Contact_V1_ContactListNIOClient: GRPCClientType {
    init(channel: GRPCChannel) {
        self.init(channel: channel, defaultCallOptions: .default, interceptors: InterceptorFactory())
    }
}
