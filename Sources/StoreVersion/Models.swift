//
//  Models.swift
//  StoreVersion
//
//  Created by Visarut Tippun on 22/11/2026.
//  Copyright © 2026 Visarut Tippun. All rights reserved.
//

import Foundation

/// An app's current listing in the App Store, as returned by the lookup API.
public struct AppStoreListing: Sendable, Equatable {
    /// The App Store ID (`trackId`), e.g. `284882215`.
    public let appID: Int

    /// The bundle identifier of the listed app.
    public let bundleIdentifier: String

    /// The latest version available in the App Store.
    public let version: AppVersion

    /// The App Store product page. Open it to let the user update.
    public let storeURL: URL

    /// Release notes for ``version``, if any.
    public let releaseNotes: String?

    /// When ``version`` was released, if the App Store reported it.
    public let releaseDate: Date?

    /// The minimum OS version required by ``version``, e.g. `"15.0"`.
    public let minimumOSVersion: String?

    public init(appID: Int,
                bundleIdentifier: String,
                version: AppVersion,
                storeURL: URL,
                releaseNotes: String? = nil,
                releaseDate: Date? = nil,
                minimumOSVersion: String? = nil) {
        self.appID = appID
        self.bundleIdentifier = bundleIdentifier
        self.version = version
        self.storeURL = storeURL
        self.releaseNotes = releaseNotes
        self.releaseDate = releaseDate
        self.minimumOSVersion = minimumOSVersion
    }
}

/// The result of comparing the installed version with the App Store version.
public struct VersionStatus: Sendable, Equatable {
    /// The version currently running.
    public let installedVersion: AppVersion

    /// The App Store listing that was compared against.
    public let listing: AppStoreListing

    public init(installedVersion: AppVersion, listing: AppStoreListing) {
        self.installedVersion = installedVersion
        self.listing = listing
    }

    /// The latest version available in the App Store.
    public var storeVersion: AppVersion {
        self.listing.version
    }

    /// `true` when the App Store version is newer than the installed version.
    public var isUpdateAvailable: Bool {
        self.storeVersion > self.installedVersion
    }
}
