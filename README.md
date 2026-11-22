# StoreVersion

**StoreVersion** checks whether a newer version of your app is available in the App Store.

It queries Apple's public [iTunes lookup API](https://performance-partners.apple.com/search-api) for your app's bundle identifier, parses the listing, and compares the store version with the installed version. It does networking and parsing only: no UI, no persistence, and no singletons. That makes it easy to call from a service or repository layer and to replace with a fake in tests.

- `async throws` API with a typed `StoreVersionError`
- Optional `countryCode` for apps that aren't sold in the US App Store
- Numeric version comparison (`1.10 > 1.9`, `1.0 == 1.0.0`)
- Swift 6 language mode with strict concurrency; all public types are `Sendable`
- No dependencies

## Requirements

- iOS 15+ / macOS 12+ / tvOS 15+
- Swift 6.0+ (Xcode 16+)

## Installation

StoreVersion is distributed through Swift Package Manager.

**Xcode:** File › Add Package Dependencies…, enter `https://github.com/knottx/StoreVersion.git`, and choose "Up to Next Major Version" from `2.1.0`.

**Package.swift:**

```swift
dependencies: [
    .package(url: "https://github.com/knottx/StoreVersion.git", from: "2.1.0"),
],
targets: [
    .target(
        name: "MyApp",
        dependencies: [
            .product(name: "StoreVersion", package: "StoreVersion"),
        ]
    ),
]
```

## Usage

```swift
import StoreVersion

let client = StoreVersionClient()
let status = try await client.checkForUpdate()

if status.isUpdateAvailable {
    print("Version \(status.storeVersion) is available (installed: \(status.installedVersion))")
    // Show your own prompt, then open status.listing.storeURL
}
```

By default the client reads `Bundle.main.bundleIdentifier` and `CFBundleShortVersionString`. You can override either one, and inject a `URLSession`:

```swift
let client = StoreVersionClient(
    bundleIdentifier: "com.example.app",  // when the App Store bundle ID differs
    installedVersion: "1.4.0",
    session: .shared
)
```

To fetch the listing without comparing versions, call `lookup`:

```swift
let listing = try await client.lookup()
listing.version           // AppVersion, e.g. 2.1.0
listing.storeURL          // App Store product page
listing.releaseNotes      // String?
listing.releaseDate       // Date?
listing.minimumOSVersion  // String?, e.g. "15.0"
listing.appID             // Int (trackId)
```

### tvOS

On tvOS, the lookup asks for the Apple TV listing (`entity=tvSoftware`). A tvOS app often shares its bundle identifier with an iOS app but has its own version numbers, so without this the client would compare against the iOS version. No setup is needed; `listing.storeURL` and `listing.minimumOSVersion` also describe the Apple TV app.

### Country code

Pass `countryCode` to search a specific App Store storefront. It must be a two-letter [ISO 3166-1 alpha-2](https://en.wikipedia.org/wiki/ISO_3166-1_alpha-2) code. Case and surrounding whitespace are ignored, so `"TH"`, `"th"`, and `" th "` are equivalent.

```swift
let status = try await client.checkForUpdate(countryCode: "th")
```

**When `countryCode` is `nil` (the default)**, no country is sent, and Apple searches its default storefront, which is the **United States**. If your app isn't sold in the US, pass a country code. Otherwise the lookup throws `StoreVersionError.appNotFound`.

A value that isn't exactly two ASCII letters (`""`, `"tha"`, `"001"`) throws `StoreVersionError.invalidCountryCode` **before** any request is made. A well-formed code is sent as-is; if Apple has no listing for your app in that store, you get `.appNotFound`.

To follow the user's region, pass it through:

```swift
let region = Locale.current.region?.identifier  // iOS 16+; use Locale.current.regionCode on iOS 15
let status = try await client.checkForUpdate(countryCode: region)
```

Some region identifiers aren't two-letter codes (for example `"001"`) and throw `.invalidCountryCode`, so handle that case or fall back to `nil`.

### Version comparison

`AppVersion` compares versions numerically, component by component. Missing trailing components count as zero:

```swift
AppVersion("1.10")! > AppVersion("1.9")!     // true
AppVersion("1.0")! == AppVersion("1.0.0")!   // true
AppVersion("2.0.1")! > AppVersion("2")!      // true
```

When parsing, surrounding whitespace and a leading `v` are ignored, and parsing stops at the first non-numeric suffix, so `"1.2.3 (45)"` becomes `1.2.3`. Strings that don't start with a number (such as `"beta"`) are rejected.

## Integrating with a clean architecture

Keep `StoreVersionClient` at the edge of your data layer. The repository turns its results and errors into your app's own types, so nothing above it imports `StoreVersion`.

```swift
import Combine  // ObservableObject
import Foundation
import StoreVersion

// Domain
struct AppUpdate: Sendable {
    let version: String
    let storeURL: URL
    let releaseNotes: String?
}

enum AppUpdateError: Error {
    case offline
    case notPublished
    case unavailable
}

protocol AppUpdateRepository: Sendable {
    /// Returns the update if one is available, or `nil` if the app is up to date.
    func availableUpdate() async throws -> AppUpdate?
}

// Data
struct StoreAppUpdateRepository: AppUpdateRepository {
    let client: StoreVersionClient
    let countryCode: String?

    func availableUpdate() async throws -> AppUpdate? {
        do {
            let status = try await client.checkForUpdate(countryCode: countryCode)
            guard status.isUpdateAvailable else { return nil }
            return AppUpdate(
                version: status.storeVersion.description,
                storeURL: status.listing.storeURL,
                releaseNotes: status.listing.releaseNotes
            )
        } catch let error as StoreVersionError {
            switch error {
            case .network: throw AppUpdateError.offline
            case .appNotFound: throw AppUpdateError.notPublished
            default: throw AppUpdateError.unavailable
            }
        }
        // CancellationError propagates unchanged.
    }
}

// Presentation
@MainActor
final class UpdatePromptViewModel: ObservableObject {
    @Published private(set) var update: AppUpdate?
    private let repository: any AppUpdateRepository

    init(repository: any AppUpdateRepository) {
        self.repository = repository
    }

    func onAppear() async {
        update = try? await repository.availableUpdate()
    }
}

// Composition root (on the main actor, e.g. in your App or SceneDelegate)
let viewModel = UpdatePromptViewModel(
    repository: StoreAppUpdateRepository(client: StoreVersionClient(), countryCode: "th")
)
```

In tests, give the view model a fake `AppUpdateRepository`. To test the repository itself, inject a `URLSession` configured with a stub `URLProtocol` (the package's own tests in `Tests/StoreVersionTests` do this).

## Error handling

Methods throw `StoreVersionError`, or `CancellationError` if the calling task is cancelled.

| Case                          | Meaning                                                                     | Typical handling                                    |
| ----------------------------- | --------------------------------------------------------------------------- | --------------------------------------------------- |
| `.invalidCountryCode(String)` | Country code isn't two ASCII letters. No request is made.                   | Programmer error; fix the input or pass `nil`.      |
| `.missingBundleIdentifier`    | No bundle ID was given and `Bundle.main` has none.                          | Configuration error.                                |
| `.missingInstalledVersion`    | No installed version was given and `CFBundleShortVersionString` is missing. | Configuration error.                                |
| `.invalidVersion(String)`     | The installed or store version isn't numeric.                               | Treat as "can't check".                             |
| `.network(URLError)`          | Transport failure (offline, timeout, TLS).                                  | Retry later; silently skip the prompt.              |
| `.httpStatus(Int)`            | The App Store returned a non-2xx status.                                    | Retry later.                                        |
| `.invalidResponse`            | The response body isn't valid lookup JSON.                                  | Treat as "can't check".                             |
| `.appNotFound`                | No app with this bundle ID in the requested store.                          | Check `countryCode`, or the app isn't released yet. |

An update check should rarely block the user. Usually the right response to any error is to skip the prompt and try again on the next launch.

## License

StoreVersion is available under the MIT license. See [LICENSE.md](LICENSE.md).
