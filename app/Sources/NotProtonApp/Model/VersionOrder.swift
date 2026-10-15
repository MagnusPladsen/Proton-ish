// Orders Proton-ish versions the way releases happen: a pre-release comes before its final
// (0.1.0-beta.4 < 0.1.0), pre-releases of the same version by their numbers (beta.2 < beta.10),
// and the numeric parts numerically (0.9.9 < 0.10.0). String comparison got the first one wrong.

import Foundation

enum VersionOrder {

    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = parse(lhs), right = parse(rhs)
        if left.core != right.core {
            return left.core.lexicographicallyPrecedes(right.core) ? .orderedAscending : .orderedDescending
        }
        switch (left.preRelease, right.preRelease) {
        case (nil, nil): return .orderedSame
        case (nil, _): return .orderedDescending
        case (_, nil): return .orderedAscending
        case (let a?, let b?): return comparePreRelease(a, b)
        }
    }

    static func isNewer(_ lhs: String, than rhs: String) -> Bool { compare(lhs, rhs) == .orderedDescending }

    private static func parse(_ version: String) -> (core: [Int], preRelease: [String]?) {
        let trimmed = version.hasPrefix("v") ? String(version.dropFirst()) : version
        let halves = trimmed.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        var core = halves[0].split(separator: ".", omittingEmptySubsequences: false).map { Int($0) ?? 0 }
        while core.count < 3 { core.append(0) }
        let preRelease = halves.count > 1 ? halves[1].split(separator: ".").map(String.init) : nil
        return (core, preRelease)
    }

    // Identifier by identifier, numbers by value and before words, a shorter list first when equal so far
    private static func comparePreRelease(_ a: [String], _ b: [String]) -> ComparisonResult {
        for (x, y) in zip(a, b) {
            switch (Int(x), Int(y)) {
            case (let m?, let n?): if m != n { return m < n ? .orderedAscending : .orderedDescending }
            case (_?, nil): return .orderedAscending
            case (nil, _?): return .orderedDescending
            case (nil, nil): if x != y { return x < y ? .orderedAscending : .orderedDescending }
            }
        }
        if a.count == b.count { return .orderedSame }
        return a.count < b.count ? .orderedAscending : .orderedDescending
    }
}
