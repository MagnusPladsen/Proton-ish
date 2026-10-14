import Foundation
import Testing

@testable import NotProtonApp

@Suite("Local signing identity")
struct LocalSigningIdentityTests {

    @Test("The identity is found in security's listing even while macOS does not trust it")
    func parsesUntrustedIdentity() {
        let output = """
        Policy: Code Signing
          Matching identities
          1) 851BBC21312B0D8F7BA17E29E630B6E7D2BD4B4B "Apple Development: someone@example.com (KFJ72LA65J)"
          2) 535F91049A2858D3FED0172FC703F3844D8BC106 "Proton-ish Local Signing" (CSSMERR_TP_NOT_TRUSTED)
             2 identities found
        """
        #expect(LocalSigningIdentity.hash(inFindIdentityOutput: output) == "535F91049A2858D3FED0172FC703F3844D8BC106")
    }

    @Test("No listing entry means no identity")
    func noIdentity() {
        #expect(LocalSigningIdentity.hash(inFindIdentityOutput: "Policy: Code Signing\n     0 identities found\n") == nil)
    }

    @Test("Steam is still signed, ad hoc, when the local identity cannot sign")
    func fallsBackToAdHoc() throws {
        let work = try scratchDirectory("steam-sign")
        defer { try? FileManager.default.removeItem(at: work) }
        let binary = work.appending(path: "tool")
        try FileManager.default.copyItem(at: URL(filePath: "/usr/bin/true"), to: binary)
        _ = try Shell.run("/usr/bin/codesign", ["--remove-signature", binary.path(percentEncoded: false)])

        try SteamInstaller.signSteamBundle(binary, identity: { "0000000000000000000000000000000000000000" })

        let details = try Shell.run("/usr/bin/codesign", ["-dv", binary.path(percentEncoded: false)])
        #expect(details.stderr.contains("Signature=adhoc"))
    }

    @Test("A bundle that is not the user's Steam is signed ad hoc, never with the keychain identity")
    func onlyUsersSteamGetsTheIdentity() throws {
        let work = try scratchDirectory("steam-sign-other")
        defer { try? FileManager.default.removeItem(at: work) }
        let binary = work.appending(path: "tool")
        try FileManager.default.copyItem(at: URL(filePath: "/usr/bin/true"), to: binary)

        try SteamInstaller.signSteamBundle(binary)

        let details = try Shell.run("/usr/bin/codesign", ["-dv", binary.path(percentEncoded: false)])
        #expect(details.stderr.contains("Signature=adhoc"))
    }
}
