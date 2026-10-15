import Foundation
import Testing

@testable import NotProtonApp

@Suite("About credits")
struct AboutCreditsTests {

    @Test("The About panel credits upstream and disclaims affiliation")
    func creditsNameUpstreamAndDisclaimAffiliation() {
        let text = AboutCredits.text
        #expect(text.contains("fork of NotProton"))
        #expect(text.contains("https://github.com/NotProtonNot/NotProton"))
        #expect(text.contains("not affiliated"))
        #expect(text.contains("Valve"))
        #expect(text.contains("CodeWeavers"))
        #expect(text.contains("Highball"))
        #expect(text.contains("GPLv3"))
        #expect(text.contains("HighballKit"))
        #expect(text.contains("highball-db"))
    }
}
