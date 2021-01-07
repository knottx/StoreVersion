//
//  StoreVersionClientTests.swift
//  StoreVersionTests
//
//  Created by Visarut Tippun on 22/11/2026.
//  Copyright © 2026 Visarut Tippun. All rights reserved.
//

import Foundation
import StoreVersion
import Testing

@Suite("StoreVersionClient")
struct StoreVersionClientTests {
    // MARK: - Success

    @Test func parsesSuccessfulLookup() async throws {
        let (client, _) = makeClient(handler: respond(json: lookupJSON(version: "2.1.0")))

        let listing = try await client.lookup()

        #expect(listing.appID == 1_234_567_890)
        #expect(listing.bundleIdentifier == "com.example.app")
        #expect(listing.version == AppVersion("2.1.0"))
        #expect(listing.storeURL == URL(string: "https://apps.apple.com/th/app/example/id1234567890"))
        #expect(listing.releaseNotes == "Bug fixes.")
        #expect(listing.releaseDate == Date(timeIntervalSince1970: 1_790_838_000))
        #expect(listing.minimumOSVersion == "15.0")
    }

    @Test func toleratesMissingOptionalFields() async throws {
        let (client, stub) = makeClient(handler: respond(json: """
        {"results": [{"trackId": 42, "version": "3.0", "currentVersionReleaseDate": "not a date"}]}
        """))

        let listing = try await client.lookup()

        let requestedBundleID = try #require(stub.requests.first?.queryValue("bundleId"))
        #expect(listing.bundleIdentifier == requestedBundleID)
        #expect(listing.storeURL == URL(string: "https://apps.apple.com/app/id42"))
        #expect(listing.releaseNotes == nil)
        #expect(listing.releaseDate == nil)
        #expect(listing.minimumOSVersion == nil)
    }

    @Test(arguments: [("1.0.0", "2.1.0", true),
                      ("2.1", "2.1.0", false),
                      ("2.1.0", "2.1.0", false),
                      ("3.0", "2.1.0", false),
                      ("2.1.0", "2.1.0.1", true)])
    func checkForUpdateComparesVersions(installed: String, store: String, expected: Bool) async throws {
        let (client, _) = makeClient(installedVersion: installed, handler: respond(json: lookupJSON(version: store)))

        let status = try await client.checkForUpdate()

        #expect(status.isUpdateAvailable == expected)
        #expect(status.installedVersion == AppVersion(installed))
        #expect(status.storeVersion == AppVersion(store))
    }

    // MARK: - Request & country code

    @Test func requestTargetsLookupEndpoint() async throws {
        let (client, stub) = makeClient(handler: respond(json: lookupJSON()))

        _ = try await client.lookup()

        let request = try #require(stub.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.scheme == "https")
        #expect(request.url?.host == "itunes.apple.com")
        #expect(request.url?.path == "/lookup")
        #expect(request.queryValue("bundleId")?.hasPrefix("com.example.") == true)
    }

    @Test func omitsCountryWhenNil() async throws {
        let (client, stub) = makeClient(handler: respond(json: lookupJSON()))

        _ = try await client.lookup(countryCode: nil)

        let request = try #require(stub.requests.first)
        #expect(request.queryNames == ["bundleId"])
    }

    @Test(arguments: [("th", "th"), ("TH", "th"), (" jp\n", "jp"), ("Us", "us")])
    func includesNormalizedCountry(input: String, expected: String) async throws {
        let (client, stub) = makeClient(handler: respond(json: lookupJSON()))

        _ = try await client.checkForUpdate(countryCode: input)

        let request = try #require(stub.requests.first)
        #expect(request.queryValue("country") == expected)
    }

    @Test(arguments: ["", "  ", "t", "tha", "t1", "001", "ไท", "é1", "u s"])
    func rejectsInvalidCountryWithoutNetworkCall(input: String) async {
        let (client, stub) = makeClient(handler: respond(json: lookupJSON()))

        await #expect(throws: StoreVersionError.invalidCountryCode(input)) {
            try await client.lookup(countryCode: input)
        }
        #expect(stub.requests.isEmpty)
    }

    // MARK: - Response errors

    @Test func emptyResultsThrowsAppNotFound() async {
        let (client, _) = makeClient(handler: respond(json: #"{"resultCount": 0, "results": []}"#))

        await #expect(throws: StoreVersionError.appNotFound) {
            try await client.lookup(countryCode: "th")
        }
    }

    @Test(arguments: ["",
                      "not json",
                      "[]",
                      #"{"resultCount": 1}"#,
                      #"{"results": {}}"#,
                      #"{"results": [{"version": "1.0"}]}"#,
                      #"{"results": [{"trackId": 1}]}"#,
                      #"{"results": [{"trackId": "1", "version": "1.0"}]}"#,
                      #"{"results": [{"trackId": 1, "version": 1.0}]}"#])
    func malformedBodyThrowsInvalidResponse(body: String) async {
        let (client, _) = makeClient(handler: respond(json: body))

        await #expect(throws: StoreVersionError.invalidResponse) {
            try await client.lookup()
        }
    }

    @Test func unparseableStoreVersionThrowsInvalidVersion() async {
        let (client, _) = makeClient(handler: respond(json: lookupJSON(version: "latest")))

        await #expect(throws: StoreVersionError.invalidVersion("latest")) {
            try await client.lookup()
        }
    }

    @Test(arguments: [301, 400, 404, 500, 503])
    func nonSuccessStatusThrowsHTTPStatus(status: Int) async {
        let (client, _) = makeClient(handler: respond(status: status, json: lookupJSON()))

        await #expect(throws: StoreVersionError.httpStatus(status)) {
            try await client.lookup()
        }
    }

    @Test(arguments: [URLError.Code.notConnectedToInternet, .timedOut, .cannotFindHost])
    func transportFailureThrowsNetwork(code: URLError.Code) async throws {
        let (client, _) = makeClient { _ in throw URLError(code) }

        let error = await #expect(throws: StoreVersionError.self) {
            try await client.lookup()
        }
        guard case let .network(urlError) = try #require(error) else {
            Issue.record("Expected .network, got \(String(describing: error))")
            return
        }
        #expect(urlError.code == code)
    }

    // MARK: - Local input validation

    @Test func emptyBundleIdentifierThrows() async {
        let client = StoreVersionClient(bundleIdentifier: "", installedVersion: "1.0")

        await #expect(throws: StoreVersionError.missingBundleIdentifier) {
            try await client.lookup()
        }
    }

    @Test func invalidInstalledVersionThrowsBeforeRequest() async {
        let (client, stub) = makeClient(installedVersion: "dev", handler: respond(json: lookupJSON()))

        await #expect(throws: StoreVersionError.invalidVersion("dev")) {
            try await client.checkForUpdate()
        }
        #expect(stub.requests.isEmpty)
    }

    @Test func cancelledTaskThrowsCancellationErrorWithoutRequest() async {
        let (client, stub) = makeClient(handler: respond(json: lookupJSON()))

        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await client.lookup()
        }

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        #expect(stub.requests.isEmpty)
    }
}
