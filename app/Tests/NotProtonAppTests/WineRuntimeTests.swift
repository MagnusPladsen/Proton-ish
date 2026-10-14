import Foundation
import Testing

@testable import NotProtonApp

@Suite("Wine runtime")
struct WineRuntimeTests {

    @Test("Every supported build is a CrossOver build")
    func supportedBuildsAreCrossOver() {
        #expect(!SupportedRunners.all.isEmpty)
        #expect(SupportedRunners.all.allSatisfy { $0.runtime == .crossover })
    }

    @Test("A rebuild keeps the runtime of the build it belongs to")
    func rebuildKeepsRuntime() throws {
        let build = try #require(SupportedRunners.all.first { !$0.rebuilds.isEmpty })
        let rebuild = try #require(build.rebuilds.first)
        #expect(build.matching(loaderSHA256: rebuild.loaderSHA256)?.runtime == build.runtime)
    }

    @Test("The runtime's raw value is the runner directory prefix")
    func rawValueIsDirectoryPrefix() {
        #expect(RuntimeKind.crossover.rawValue == "crossover")
    }
}
