//
//  StoreVersionClient.swift
//  StoreVersion
//
//  Created by Visarut Tippun on 22/11/2026.
//  Copyright © 2026 Visarut Tippun. All rights reserved.
//

import Foundation

/// Looks up an app in the App Store and compares the store version with the
/// installed version.
///
/// The client is a lightweight, immutable `Sendable` value: create one in your
/// service or data-source layer and share it freely across tasks.
///
/// ```swift
/// let client = StoreVersionClient()
/// let status = try await client.checkForUpdate(countryCode: "th")
/// if status.isUpdateAvailable { … }
/// ```
///
/// ## Country code
/// Every request method takes an optional `countryCode`, the two-letter
/// ISO 3166-1 alpha-2 code of the store to search (for example `"th"` or
/// `"JP"`). Case and surrounding whitespace are ignored. When `countryCode` is
/// `nil`, the lookup uses Apple's default storefront, which is the
/// United States store. Apps not sold in the US must pass a country code or the
/// lookup throws ``StoreVersionError/appNotFound``.
public struct StoreVersionClient: Sendable {
    private let bundleIdentifier: String?
    private let installedVersion: String?
    private let session: URLSession

    /// Creates a client.
    ///
    /// - Parameters:
    ///   - bundleIdentifier: The bundle identifier to look up. Defaults to
    ///     `Bundle.main.bundleIdentifier`. Pass a value if your App Store
    ///     bundle identifier differs from the running bundle.
    ///   - installedVersion: The version to compare against. Defaults to
    ///     `CFBundleShortVersionString` from `Bundle.main`.
    ///   - session: The URL session used for requests. Defaults to
    ///     `URLSession.shared`. Inject a configured session to customize
    ///     timeouts or to stub networking in tests.
    public init(bundleIdentifier: String? = nil,
                installedVersion: String? = nil,
                session: URLSession = .shared) {
        self.bundleIdentifier = bundleIdentifier ?? Bundle.main.bundleIdentifier
        self.installedVersion = installedVersion
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        self.session = session
    }

    /// Fetches the app's current App Store listing.
    ///
    /// - Parameter countryCode: The two-letter store country code, or `nil`
    ///   for Apple's default (US) store.
    /// - Throws: ``StoreVersionError``, or `CancellationError` if the task is
    ///   cancelled.
    public func lookup(countryCode: String? = nil) async throws -> AppStoreListing {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else {
            throw StoreVersionError.missingBundleIdentifier
        }
        let request = try LookupRequest.make(bundleIdentifier: bundleIdentifier, countryCode: countryCode)

        try Task.checkCancellation()
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await self.session.data(for: request)
        } catch {
            if Task.isCancelled {
                throw CancellationError()
            }
            throw StoreVersionError.network(error as? URLError ?? URLError(.unknown))
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw StoreVersionError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw StoreVersionError.httpStatus(httpResponse.statusCode)
        }
        return try LookupResponse.parse(data, requestedBundleIdentifier: bundleIdentifier)
    }

    /// Fetches the App Store listing and compares it with the installed version.
    ///
    /// - Parameter countryCode: The two-letter store country code, or `nil`
    ///   for Apple's default (US) store.
    /// - Returns: The comparison; check ``VersionStatus/isUpdateAvailable``.
    /// - Throws: ``StoreVersionError``, or `CancellationError` if the task is
    ///   cancelled. Installed-version problems are reported before any request
    ///   is made.
    public func checkForUpdate(countryCode: String? = nil) async throws -> VersionStatus {
        guard let installedVersion else {
            throw StoreVersionError.missingInstalledVersion
        }
        guard let installed = AppVersion(installedVersion) else {
            throw StoreVersionError.invalidVersion(installedVersion)
        }
        let listing = try await self.lookup(countryCode: countryCode)
        return VersionStatus(installedVersion: installed, listing: listing)
    }
}
