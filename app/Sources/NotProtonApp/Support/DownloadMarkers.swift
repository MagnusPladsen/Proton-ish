import Darwin
import Foundation

// macOS marks a downloaded app as quarantined, and copies of its files keep the mark. Gatekeeper
// then refuses a marked helper that runs outside the app the user approved, like highball-env
// started from Steam's launch (#79).
enum DownloadMarkers {
    static let quarantine = "com.apple.quarantine"
    static let all = [quarantine, "com.apple.provenance"]

    static func isQuarantined(_ file: URL) -> Bool {
        getxattr(file.path(percentEncoded: false), quarantine, nil, 0, 0, XATTR_NOFOLLOW) >= 0
    }

    /// Best effort: a mark that can't be removed only means Gatekeeper may still ask.
    static func remove(from file: URL) {
        for name in all {
            _ = removexattr(file.path(percentEncoded: false), name, XATTR_NOFOLLOW)
        }
    }
}
