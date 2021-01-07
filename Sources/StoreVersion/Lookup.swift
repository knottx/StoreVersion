//
//  Lookup.swift
//  StoreVersion
//
//  Created by Visarut Tippun on 22/11/2026.
//  Copyright © 2026 Visarut Tippun. All rights reserved.
//

import Foundation

/// Builds iTunes Search API lookup requests.
/// See https://performance-partners.apple.com/search-api
enum LookupRequest {
    static let endpoint = URL(string: "https://itunes.apple.com/lookup")!

    static func make(bundleIdentifier: String, countryCode: String?) throws -> URLRequest {
        var components = URLComponents(url: self.endpoint, resolvingAgainstBaseURL: false)!
        var queryItems = [URLQueryItem(name: "bundleId", value: bundleIdentifier)]
        if let countryCode {
            try queryItems.append(URLQueryItem(name: "country", value: self.normalize(countryCode: countryCode)))
        }
        components.queryItems = queryItems

        // Version checks must not be answered from a stale local cache.
        return URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData)
    }

    /// Trims whitespace and lowercases; requires exactly two ASCII letters.
    static func normalize(countryCode: String) throws -> String {
        let code = countryCode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard code.count == 2, code.allSatisfy({ $0.isASCII && $0.isLetter }) else {
            throw StoreVersionError.invalidCountryCode(countryCode)
        }
        return code
    }
}

/// Decodes the lookup JSON into an ``AppStoreListing``.
enum LookupResponse {
    private struct Body: Decodable {
        let results: [Item]
    }

    private struct Item: Decodable {
        let trackId: Int?
        let bundleId: String?
        let version: String?
        let trackViewUrl: String?
        let releaseNotes: String?
        let currentVersionReleaseDate: String?
        let minimumOsVersion: String?
    }

    static func parse(_ data: Data, requestedBundleIdentifier: String) throws -> AppStoreListing {
        let body: Body
        do {
            body = try JSONDecoder().decode(Body.self, from: data)
        } catch {
            throw StoreVersionError.invalidResponse
        }

        guard let result = body.results.first else {
            throw StoreVersionError.appNotFound
        }
        guard let appID = result.trackId, let rawVersion = result.version else {
            throw StoreVersionError.invalidResponse
        }
        guard let version = AppVersion(rawVersion) else {
            throw StoreVersionError.invalidVersion(rawVersion)
        }

        let storeURL = result.trackViewUrl.flatMap(URL.init(string:))
            ?? URL(string: "https://apps.apple.com/app/id\(appID)")!

        return AppStoreListing(appID: appID,
                               bundleIdentifier: result.bundleId ?? requestedBundleIdentifier,
                               version: version,
                               storeURL: storeURL,
                               releaseNotes: result.releaseNotes,
                               releaseDate: result.currentVersionReleaseDate.flatMap(self.parseDate),
                               minimumOSVersion: result.minimumOsVersion)
    }

    private static func parseDate(_ string: String) -> Date? {
        ISO8601DateFormatter().date(from: string)
    }
}
