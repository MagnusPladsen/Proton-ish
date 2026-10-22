import Foundation
import Testing

@testable import HighballEnvCore

@Suite("HighballKit pin")
struct HighballKitPinTests {

    // Launch logs and highball-db reports quote this constant, so a hand bump of the pin that
    // forgets it would mislabel every launch
    @Test("The version highball-env prints is the HighballKit version Package.swift pins")
    func constantMatchesPin() throws {
        let manifest = URL(filePath: #filePath)
            .deletingLastPathComponent()  // HighballEnvCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // app
            .appending(path: "Package.swift")
        let source = try String(contentsOf: manifest, encoding: .utf8)
        let pin = try #require(
            source.firstMatch(of: #/gauthierpiarrette/highball", exact: "([^"]+)"/#)?.output.1)
        #expect(HighballEnvCore.highballKitVersion == String(pin))
    }
}
