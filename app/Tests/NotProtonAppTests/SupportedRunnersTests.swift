import Testing

@testable import NotProtonApp

@Suite("Supported runners")
struct SupportedRunnersTests {
    @Test("The CrossOver version list leaves out Highball's builds")
    func crossOverListHasNoHighballBuilds() {
        let list = SupportedRunners.crossOverVersionList
        let leaked = SupportedRunners.all.filter { $0.runtime == .highball && list.contains($0.releaseVersion) }
        #expect(leaked.isEmpty, "\(list)")
    }
}
