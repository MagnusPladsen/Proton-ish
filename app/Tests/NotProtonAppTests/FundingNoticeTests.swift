import Foundation
import Testing

@testable import NotProtonApp

@Suite("Funding notice")
struct FundingNoticeTests {

    private func defaults() -> UserDefaults {
        let name = "np-funding-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("The notice is due on a fresh install")
    func dueWhenNeverSeen() {
        #expect(FundingNotice.isDue(defaults()))
    }

    @Test("The notice is not due again once it has been seen")
    func notDueOnceSeen() {
        let defaults = defaults()
        FundingNotice.markSeen(defaults)
        #expect(!FundingNotice.isDue(defaults))
    }
}
