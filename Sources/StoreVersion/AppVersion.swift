//
//  AppVersion.swift
//  StoreVersion
//
//  Created by Visarut Tippun on 22/11/2026.
//  Copyright © 2026 Visarut Tippun. All rights reserved.
//

import Foundation

/// A numeric, dot-separated app version such as `1.2.3`.
///
/// Comparison is component-wise and numeric, so `1.10` is newer than `1.9`.
/// Missing trailing components count as zero, so `1.0`, `1.0.0`, and `1`
/// are equal.
///
/// Parsing is lenient about decoration but strict about the number:
/// surrounding whitespace and a leading `v`/`V` are ignored, the version
/// must start with a digit, and parsing stops at the first character that
/// is not part of a `digits(.digits)*` sequence. For example, `"v2.1 (45)"`
/// parses as `2.1`, while `"beta"` and `".1"` fail to parse.
public struct AppVersion: Sendable, Hashable, Comparable, LosslessStringConvertible {
    /// The numeric components, in order of significance.
    public let components: [Int]

    /// Creates a version from numeric components. Returns `nil` if
    /// `components` is empty or contains a negative number.
    public init?(components: [Int]) {
        guard !components.isEmpty, components.allSatisfy({ $0 >= 0 }) else { return nil }
        self.components = components
    }

    /// Parses a version string. Returns `nil` if it doesn't start with a number.
    public init?(_ description: String) {
        var text = Substring(description.trimmingCharacters(in: .whitespacesAndNewlines))
        if text.first == "v" || text.first == "V" {
            text = text.dropFirst()
        }

        var components: [Int] = []
        var remainder = text[...]
        while let first = remainder.first, first.isASCII, first.isNumber {
            let digits = remainder.prefix { $0.isASCII && $0.isNumber }
            guard let value = Int(digits) else { return nil } // Overflow.
            components.append(value)
            remainder = remainder.dropFirst(digits.count)

            // Continue only on `.` followed by another digit.
            guard remainder.first == ".",
                  let next = remainder.dropFirst().first, next.isASCII, next.isNumber
            else { break }
            remainder = remainder.dropFirst()
        }

        self.init(components: components)
    }

    public var description: String {
        self.components.map(String.init).joined(separator: ".")
    }

    /// Components with trailing zeros removed; used for equality and hashing.
    private var significantComponents: ArraySlice<Int> {
        let significantCount = (self.components.lastIndex { $0 != 0 } ?? -1) + 1
        return self.components.prefix(significantCount)
    }

    public static func ==(lhs: AppVersion, rhs: AppVersion) -> Bool {
        lhs.significantComponents == rhs.significantComponents
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(Array(self.significantComponents))
    }

    public static func <(lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right {
                return left < right
            }
        }
        return false
    }
}
