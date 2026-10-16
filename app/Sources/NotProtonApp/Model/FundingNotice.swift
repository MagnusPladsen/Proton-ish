// Whether the note on who funds Wine on the Mac still has to be shown on launch

import Foundation

enum FundingNotice {
    private static let seenKey = "fundingNoticeSeen"

    static func isDue(_ defaults: UserDefaults = .standard) -> Bool {
        !defaults.bool(forKey: seenKey)
    }

    static func markSeen(_ defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: seenKey)
    }
}
