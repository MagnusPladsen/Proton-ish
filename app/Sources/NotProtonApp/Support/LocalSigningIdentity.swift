// A self-signed code signing identity in the login keychain. Steam signed with it keeps the same
// designated requirement across re-signs, so macOS keeps its privacy permissions (Accessibility,
// Input Monitoring) instead of asking again after every install.

import Foundation

enum LocalSigningIdentity {

    static let name = "Proton-ish Local Signing"

    static var loginKeychain: URL {
        SupportPaths.home.appending(path: "Library/Keychains/login.keychain-db")
    }

    // codesign accepts an untrusted identity by its SHA-1, so trust settings (which prompt) are not needed
    static func hash(inFindIdentityOutput output: String) -> String? {
        for line in output.split(separator: "\n") where line.contains("\"\(name)\"") {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            if let hash = fields.first(where: { $0.count == 40 && $0.allSatisfy(\.isHexDigit) }) {
                return String(hash)
            }
        }
        return nil
    }

    static func find() -> String? {
        guard let result = try? Shell.run("/usr/bin/security", ["find-identity", "-p", "codesigning"]),
              result.succeeded else { return nil }
        return hash(inFindIdentityOutput: result.stdout)
    }

    static func ensure() -> String? {
        if let existing = find() { return existing }
        do {
            try create()
        } catch {
            AppLog.note("local signing identity not created: \(error)")
            return nil
        }
        return find()
    }

    static func create() throws {
        let work = FileManager.default.temporaryDirectory.appending(path: "np-identity-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        let key = work.appending(path: "key.pem").path(percentEncoded: false)
        let certificate = work.appending(path: "cert.pem").path(percentEncoded: false)
        let bundle = work.appending(path: "identity.p12").path(percentEncoded: false)
        // Only lives for the import; the key is protected by the keychain afterwards
        let passphrase = UUID().uuidString

        try run("/usr/bin/openssl", [
            "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "3650",
            "-keyout", key, "-out", certificate, "-subj", "/CN=\(name)",
            "-addext", "extendedKeyUsage=critical,codeSigning",
            "-addext", "keyUsage=critical,digitalSignature",
            "-addext", "basicConstraints=critical,CA:false",
        ])
        try run("/usr/bin/openssl", [
            "pkcs12", "-export", "-inkey", key, "-in", certificate, "-out", bundle, "-passout", "pass:\(passphrase)",
        ])
        try run("/usr/bin/security", [
            "import", bundle, "-k", loginKeychain.path(percentEncoded: false), "-P", passphrase, "-T", "/usr/bin/codesign",
        ])
    }

    private static func run(_ tool: String, _ arguments: [String]) throws {
        let result = try Shell.run(tool, arguments)
        guard result.succeeded else {
            throw StepFailure(step: String(localized: "Create the signing identity"),
                              detail: result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
