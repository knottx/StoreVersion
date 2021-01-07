//
//  StoreVersionError.swift
//  StoreVersion
//
//  Created by Visarut Tippun on 22/11/2026.
//  Copyright © 2026 Visarut Tippun. All rights reserved.
//

import Foundation

/// Errors thrown by ``StoreVersionClient``.
///
/// Task cancellation is reported as Swift's `CancellationError`, not as a
/// case of this type.
public enum StoreVersionError: Error, Sendable, Equatable {
    /// The country code is not a two-letter ISO 3166-1 alpha-2 code.
    /// The associated value is the code as passed in.
    case invalidCountryCode(String)

    /// No bundle identifier was supplied and `Bundle.main` has none.
    case missingBundleIdentifier

    /// No installed version was supplied and `Bundle.main` has no
    /// `CFBundleShortVersionString`.
    case missingInstalledVersion

    /// A version string (installed or from the App Store) is not a valid
    /// ``AppVersion``. The associated value is the original string.
    case invalidVersion(String)

    /// The request failed at the transport level (offline, timeout, TLS, …).
    case network(URLError)

    /// The App Store responded with a non-2xx HTTP status code.
    case httpStatus(Int)

    /// The response body was not the expected lookup JSON, or a required
    /// field (`trackId`, `version`) was missing.
    case invalidResponse

    /// The lookup succeeded but returned no app for this bundle identifier in
    /// the requested store, e.g. the app isn't released in that country.
    case appNotFound
}
