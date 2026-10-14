// A self-signed code signing identity in Proton-ish's own keychain. Steam signed with it keeps the
// same designated requirement across re-signs, so macOS keeps its privacy permissions
// (Accessibility, Input Monitoring) instead of asking again after every install. Proton-ish holds
// the keychain's password, so it can let codesign use the key without asking the user.

import Foundation

enum LocalSigningIdentity {

    static let name = "Proton-ish Local Signing"

    static var keychain: URL { SupportPaths.support.appending(path: "signing.keychain-db") }
    static var passwordFile: URL { SupportPaths.support.appending(path: "signing.keychain-password") }

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

    static func searchList(fromListKeychainsOutput output: String) -> [String] {
        output.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
            .filter { !$0.isEmpty }
    }

    // nil when the keychain is already listed
    static func searchList(_ current: [String], adding path: String) -> [String]? {
        current.contains(path) ? nil : current + [path]
    }

    // nil when the keychain is not listed
    static func searchList(_ current: [String], removing path: String) -> [String]? {
        current.contains(path) ? current.filter { $0 != path } : nil
    }

    // Before the support folder (and the keychain in it) is deleted
    static func removeFromSearchList(_ keychain: URL = keychain) {
        guard let listed = try? Shell.run("/usr/bin/security", ["list-keychains", "-d", "user"]), listed.succeeded,
              let updated = searchList(searchList(fromListKeychainsOutput: listed.stdout),
                                       removing: keychain.path(percentEncoded: false)),
              !updated.isEmpty else { return }
        _ = try? Shell.run("/usr/bin/security", ["list-keychains", "-d", "user", "-s"] + updated)
    }

    static func find(in keychain: URL = keychain) -> String? {
        guard let result = try? Shell.run("/usr/bin/security",
                                          ["find-identity", "-p", "codesigning", keychain.path(percentEncoded: false)]),
              result.succeeded else { return nil }
        return hash(inFindIdentityOutput: result.stdout)
    }

    // The identity to sign Steam with, creating the keychain the first time. nil means sign ad hoc.
    static func ensure() -> String? {
        do {
            if !FileManager.default.fileExists(atPath: keychain.path(percentEncoded: false)) {
                try create(keychain: keychain, passwordFile: passwordFile)
            }
            try unlock(keychain: keychain, passwordFile: passwordFile)
            try addToSearchList(keychain)
        } catch {
            AppLog.note("local signing identity unavailable: \(error)")
            return nil
        }
        return find(in: keychain)
    }

    static func create(keychain: URL, passwordFile: URL) throws {
        let password = UUID().uuidString + UUID().uuidString
        try FileManager.default.createDirectory(at: passwordFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(password.utf8).write(to: passwordFile, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: passwordFile.path(percentEncoded: false))

        let path = keychain.path(percentEncoded: false)
        try run("/usr/bin/security", ["create-keychain", "-p", password, path])
        // No auto-lock: Proton-ish unlocks it before each signature anyway
        try run("/usr/bin/security", ["set-keychain-settings", path])
        try run("/usr/bin/security", ["unlock-keychain", "-p", password, path])
        try importIdentity(into: path)
        // Lets codesign use the key without a prompt; this needs the password we hold
        try run("/usr/bin/security", ["set-key-partition-list", "-S", "apple-tool:,apple:", "-s", "-k", password, path])
    }

    private static func importIdentity(into keychain: String) throws {
        let work = FileManager.default.temporaryDirectory.appending(path: "np-identity-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        let key = work.appending(path: "key.pem").path(percentEncoded: false)
        let certificate = work.appending(path: "cert.pem").path(percentEncoded: false)
        let bundle = work.appending(path: "identity.p12").path(percentEncoded: false)
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
        try run("/usr/bin/security", ["import", bundle, "-k", keychain, "-P", passphrase, "-T", "/usr/bin/codesign"])
    }

    private static func unlock(keychain: URL, passwordFile: URL) throws {
        let password = try String(contentsOf: passwordFile, encoding: .utf8)
        try run("/usr/bin/security", ["unlock-keychain", "-p", password, keychain.path(percentEncoded: false)])
    }

    // codesign only finds identities in keychains on the user's search list
    private static func addToSearchList(_ keychain: URL) throws {
        let listed = try Shell.run("/usr/bin/security", ["list-keychains", "-d", "user"])
        guard listed.succeeded else { return }
        let current = searchList(fromListKeychainsOutput: listed.stdout)
        guard let updated = searchList(current, adding: keychain.path(percentEncoded: false)) else { return }
        try run("/usr/bin/security", ["list-keychains", "-d", "user", "-s"] + updated)
    }

    private static func run(_ tool: String, _ arguments: [String]) throws {
        let result = try Shell.run(tool, arguments)
        guard result.succeeded else {
            throw StepFailure(step: String(localized: "Create the signing identity"),
                              detail: result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
