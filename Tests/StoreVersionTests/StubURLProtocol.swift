//
//  StubURLProtocol.swift
//  StoreVersionTests
//
//  Created by Visarut Tippun on 22/11/2026.
//  Copyright © 2026 Visarut Tippun. All rights reserved.
//

import Foundation
import StoreVersion

/// A `URLProtocol` that answers requests from in-memory handlers, so tests
/// never touch the network.
///
/// Handlers are keyed by the request's `bundleId` query item. Each test uses a
/// unique bundle identifier, which keeps tests isolated when Swift Testing runs
/// them in parallel.
final class StubURLProtocol: URLProtocol {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let stub = Registry.shared.stub(for: request) else {
            self.client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        stub.record(self.request)
        do {
            let (response, data) = try stub.handler(self.request)
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: data)
            self.client?.urlProtocolDidFinishLoading(self)
        } catch {
            self.client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

/// A registered handler plus the requests it has received.
final class Stub: @unchecked Sendable {
    let handler: StubURLProtocol.Handler
    private let lock = NSLock()
    private var _requests: [URLRequest] = []

    init(handler: @escaping StubURLProtocol.Handler) {
        self.handler = handler
    }

    var requests: [URLRequest] {
        self.lock.withLock { self._requests }
    }

    fileprivate func record(_ request: URLRequest) {
        self.lock.withLock { self._requests.append(request) }
    }
}

private final class Registry: @unchecked Sendable {
    static let shared = Registry()

    private let lock = NSLock()
    private var stubs: [String: Stub] = [:]

    func register(_ stub: Stub, for bundleIdentifier: String) {
        self.lock.withLock { self.stubs[bundleIdentifier] = stub }
    }

    func stub(for request: URLRequest) -> Stub? {
        guard let url = request.url,
              let bundleID = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                  .queryItems?.first(where: { $0.name == "bundleId" })?.value
        else { return nil }
        return self.lock.withLock { self.stubs[bundleID] }
    }
}

// MARK: - Test helpers

/// Creates a client wired to a fresh stub with a unique bundle identifier.
func makeClient(installedVersion: String? = "1.0.0",
                handler: @escaping StubURLProtocol.Handler) -> (StoreVersionClient, Stub) {
    let bundleIdentifier = "com.example.\(UUID().uuidString)"
    let stub = Stub(handler: handler)
    Registry.shared.register(stub, for: bundleIdentifier)

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    let client = StoreVersionClient(bundleIdentifier: bundleIdentifier,
                                    installedVersion: installedVersion,
                                    session: URLSession(configuration: configuration))
    return (client, stub)
}

/// Returns a handler that responds with `status` and `body`.
func respond(status: Int = 200, json body: String) -> StubURLProtocol.Handler {
    { request in
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (response, Data(body.utf8))
    }
}

/// A lookup response containing one app with the given version.
func lookupJSON(version: String = "2.1.0") -> String {
    """
    {
      "resultCount": 1,
      "results": [{
        "trackId": 1234567890,
        "bundleId": "com.example.app",
        "version": "\(version)",
        "trackViewUrl": "https://apps.apple.com/th/app/example/id1234567890",
        "releaseNotes": "Bug fixes.",
        "currentVersionReleaseDate": "2026-10-01T07:00:00Z",
        "minimumOsVersion": "15.0"
      }]
    }
    """
}

extension URLRequest {
    func queryValue(_ name: String) -> String? {
        URLComponents(url: self.url!, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == name })?.value
    }

    var queryNames: [String] {
        URLComponents(url: self.url!, resolvingAgainstBaseURL: false)?.queryItems?.map(\.name) ?? []
    }
}
