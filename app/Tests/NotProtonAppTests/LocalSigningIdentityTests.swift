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

    @Test("The search list is read as one path per keychain, quotes and indentation stripped")
    func parsesSearchList() {
        let output = """
            "/Users/me/Library/Keychains/login.keychain-db"
            "/Users/me/Library/Application Support/protonish/signing.keychain-db"
        """
        #expect(LocalSigningIdentity.searchList(fromListKeychainsOutput: output) == [
            "/Users/me/Library/Keychains/login.keychain-db",
            "/Users/me/Library/Application Support/protonish/signing.keychain-db",
        ])
    }

    @Test("Adding the signing keychain keeps every existing keychain, and adds it once")
    func addsToSearchListOnce() {
        let login = "/Users/me/Library/Keychains/login.keychain-db"
        let ours = "/Users/me/Library/Application Support/protonish/signing.keychain-db"
        #expect(LocalSigningIdentity.searchList([login], adding: ours) == [login, ours])
        #expect(LocalSigningIdentity.searchList([login, ours], adding: ours) == nil)
    }

    @Test("Removing the signing keychain leaves every other keychain listed")
    func removesFromSearchList() {
        let login = "/Users/me/Library/Keychains/login.keychain-db"
        let ours = "/Users/me/Library/Application Support/protonish/signing.keychain-db"
        #expect(LocalSigningIdentity.searchList([login, ours], removing: ours) == [login])
        #expect(LocalSigningIdentity.searchList([login], removing: ours) == nil)
    }

    @Test("The identity is created in its own keychain, never the login keychain")
    func createsInOwnKeychain() throws {
        let work = try scratchDirectory("signing-keychain")
        defer { try? FileManager.default.removeItem(at: work) }
        let keychain = work.appending(path: "signing.keychain-db")
        let password = work.appending(path: "signing.keychain-password")

        try LocalSigningIdentity.create(keychain: keychain, passwordFile: password)

        #expect(LocalSigningIdentity.find(in: keychain) != nil)
        let mode = try FileManager.default.attributesOfItem(atPath: password.path(percentEncoded: false))[.posixPermissions] as? Int
        #expect(mode == 0o600)
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
