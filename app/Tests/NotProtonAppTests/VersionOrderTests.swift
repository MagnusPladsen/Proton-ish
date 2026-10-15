import Foundation
import Testing

@testable import NotProtonApp

@Suite("Version order")
struct VersionOrderTests {

    @Test("A final release is newer than its pre-releases")
    func finalBeatsPreRelease() {
        #expect(VersionOrder.isNewer("0.1.0", than: "0.1.0-beta.4"))
        #expect(!VersionOrder.isNewer("0.1.0-beta.4", than: "0.1.0"))
    }

    @Test("Pre-releases of one version order by their numbers",
          arguments: [("0.1.0-beta.2", "0.1.0-beta.10"), ("0.1.0-alpha.1", "0.1.0-beta.1"), ("0.1.0-beta", "0.1.0-beta.1"), ("0.1.0-beta.1", "0.1.0-rc.1")])
    func preReleaseOrder(older: String, newer: String) {
        #expect(VersionOrder.isNewer(newer, than: older))
    }

    @Test("Numeric parts compare as numbers, missing parts as zero")
    func numericParts() {
        #expect(VersionOrder.isNewer("0.10.0", than: "0.9.9"))
        #expect(VersionOrder.isNewer("1.0.0", than: "0.1.0-beta.4"))
        #expect(VersionOrder.compare("1.0", "1.0.0") == .orderedSame)
        #expect(VersionOrder.compare("v1.1.7", "1.1.7") == .orderedSame)
    }

    @Test("Installed betas accept the final release as an update")
    func buildOrdering() {
        let beta = DeploymentContent.Build(version: "0.1.0-beta.4", builtAt: 100)
        let final = DeploymentContent.Build(version: "0.1.0", builtAt: 90)
        #expect(final.isNewer(than: beta))
        #expect(!beta.isNewer(than: final))
    }
}
