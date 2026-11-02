import Foundation
import Testing

@testable import NotProtonApp

@Suite("Valve package manifest")
struct ValvePackageManifestTests {

    @Test("The shipped manifest pins every Valve file to a package")
    func shippedManifestIsComplete() throws {
        let manifest = try ValvePackageManifest.bundled()

        // Twelve files out of two packages, over three hosts that serve identical bytes.
        #expect(manifest.files.count == 12)
        #expect(manifest.packages.count == 2)
        #expect(manifest.bases.count == 3)

        // Akamai first. The order is the order they are tried in, so it is not
        // incidental: the fallbacks exist for when the first host is unreachable.
        #expect(manifest.bases.first?.host() == "client-update.akamai.steamstatic.com")

        // Both packages are named for their own sha1, which is the pin that stops a
        // client update from moving the contents underneath a fixed name.
        for package in manifest.packages {
            let sha1 = package.file.split(separator: ".").last.map(String.init) ?? ""
            #expect(sha1.count == 40, "\(package.file) does not end in a package sha1")
        }

        // The bundle is pinned the same way but is not a bridge input, so it is absent
        // from the counts above. It comes wrapped twice, as a tar.gz inside the zip.
        let bundle = try #require(manifest.bundle)
        #expect(bundle.file == "appdmg_osx.zip.984652b88a9737e3f4e77c656d9ffa67d5042c2c")
        #expect(bundle.sha256 == "8bf4ce8b4bcbc50f642988c955559f605e7a877372116e7a2b3fd1355004bedb")
        #expect(bundle.innerArchive == "SteamMacBootstrapper.tar.gz")
        #expect(bundle.bundleName == "Steam.app")

        let bundleSHA1 = bundle.file.split(separator: ".").last.map(String.init) ?? ""
        #expect(bundleSHA1.count == 40, "\(bundle.file) does not end in a package sha1")
    }

    // Optional because only repair reads it. A manifest without one has to parse, or
    // every consumer would be made to carry a row none of them touch.
    @Test("A manifest with no bundle row parses, and repair is what reports it missing")
    func bundleRowIsOptional() throws {
        let hash = String(repeating: "a", count: 64)
        let manifest = try ValvePackageManifest.parse(
            """
            base     https://example.invalid/client
            package  win64  bins_win64.zip.aa  \(hash)
            file     tier0_s64.dll  win64  tier0_s64.dll  \(hash)
            """
        )

        #expect(manifest.bundle == nil)
    }

    // Both manifests are written by hand and read by different consumers, so only a test stops
    // them drifting. No row means unfetchable, and no entry means a file nothing consumes.
    @Test("Every valve payload entry has exactly one package row, and the reverse")
    func agreesWithThePayloadManifest() throws {
        let payload = try PayloadManifest.bundled()
        let packages = try ValvePackageManifest.bundled()

        let fromPayload = Set(payload.paths(origin: .valve))
        let fromPackages = Set(packages.files.map(\.bridgePath))

        #expect(fromPayload == fromPackages)
        #expect(fromPackages.count == packages.files.count, "a bridge path is listed twice")
    }

    @Test("A package is opened once per archive entry, not once per bridge path")
    func innerPathsAreDeduplicated() throws {
        let manifest = try ValvePackageManifest.bundled()

        // Six of the twelve come from the Linux package under legacycompat, and two are also staged
        // at the bridge root, so eight bridge paths resolve to six entries in that archive.
        let linux = manifest.files.filter { $0.package == "linux" }
        #expect(linux.count == 8)
        #expect(manifest.innerPaths(package: "linux").count == 6)
        // The other four, both libraries in their 32-bit and 64-bit builds, come from win64.
        #expect(manifest.innerPaths(package: "win64").count == 4)
    }

    @Test("Row kinds parse into their own collections")
    func parsesEachRowKind() throws {
        let manifest = try ValvePackageManifest.parse(
            """
            # a comment
              # an indented comment

            base     https://example.invalid/client
            package  win64  bins_win64.zip.aa  \(String(repeating: "a", count: 64))
            file     tier0_s64.dll  win64  tier0_s64.dll  \(String(repeating: "b", count: 64))
            bundle   appdmg_osx.zip.cc  \(String(repeating: "c", count: 64))  SteamMacBootstrapper.tar.gz  Steam.app
            """
        )

        #expect(manifest.bases.map(\.absoluteString) == ["https://example.invalid/client"])
        #expect(manifest.packages == [
            ValvePackage(id: "win64", file: "bins_win64.zip.aa", sha256: String(repeating: "a", count: 64)),
        ])
        #expect(manifest.files == [
            ValveFile(
                bridgePath: "tier0_s64.dll", package: "win64",
                innerPath: "tier0_s64.dll", sha256: String(repeating: "b", count: 64)
            ),
        ])
        #expect(manifest.bundle == ValveBundle(
            file: "appdmg_osx.zip.cc", sha256: String(repeating: "c", count: 64),
            innerArchive: "SteamMacBootstrapper.tar.gz", bundleName: "Steam.app"
        ))
    }

    // Every one of these has to throw. A skipped row means a file that is silently not
    // fetched, and the failure then surfaces as a launch that breaks for another reason.
    @Test("A malformed manifest is refused rather than partly read")
    func refusesMalformed() {
        let hash = String(repeating: "a", count: 64)
        let good = """
            base     https://example.invalid/client
            package  win64  bins_win64.zip.aa  \(hash)
            file     tier0_s64.dll  win64  tier0_s64.dll  \(hash)
            """

        func parse(_ text: String) throws { _ = try ValvePackageManifest.parse(text) }

        #expect(throws: StepFailure.self) { try parse("nonsense one two") }
        #expect(throws: StepFailure.self) { try parse("") }
        #expect(throws: StepFailure.self) { try parse("# only comments") }

        // A base that is not https, and one that is not a URL at all.
        #expect(throws: StepFailure.self) { try parse(good.replacingOccurrences(of: "https://", with: "http://")) }
        #expect(throws: StepFailure.self) { try parse("base not-a-url\n" + good) }

        // Missing and extra fields, per row kind.
        #expect(throws: StepFailure.self) { try parse("base") }
        #expect(throws: StepFailure.self) { try parse("package win64 bins_win64.zip.aa") }
        #expect(throws: StepFailure.self) { try parse("file tier0_s64.dll win64 tier0_s64.dll") }
        #expect(throws: StepFailure.self) { try parse(good + " extra") }

        // A hash that is short, uppercase, or not hex.
        #expect(throws: StepFailure.self) { try parse(good.replacingOccurrences(of: hash, with: "aa")) }
        #expect(throws: StepFailure.self) { try parse(good.replacingOccurrences(of: hash, with: hash.uppercased())) }
        #expect(throws: StepFailure.self) {
            try parse(good.replacingOccurrences(of: hash, with: String(repeating: "z", count: 64)))
        }

        // A manifest with no host, no package, or no file.
        #expect(throws: StepFailure.self) { try parse(good.replacingOccurrences(of: "base     https://example.invalid/client\n", with: "")) }
        #expect(throws: StepFailure.self) { try parse("base https://example.invalid/client") }
        #expect(throws: StepFailure.self) {
            try parse("base https://example.invalid/client\npackage win64 bins_win64.zip.aa \(hash)")
        }

        // A file naming a package that was never declared.
        #expect(throws: StepFailure.self) { try parse(good.replacingOccurrences(of: "file     tier0_s64.dll  win64", with: "file     tier0_s64.dll  win66")) }

        // The same bridge path or package id twice.
        #expect(throws: StepFailure.self) { try parse(good + "\nfile     tier0_s64.dll  win64  other.dll  \(hash)") }
        #expect(throws: StepFailure.self) { try parse(good + "\npackage  win64  other.zip.bb  \(hash)") }

        // A declared package that no file row uses would be downloaded for nothing.
        #expect(throws: StepFailure.self) {
            try parse(good + "\npackage  linux  bins_misc_ubuntu12.zip.bb  \(hash)")
        }

        // Two bridge paths sharing one archive entry but disagreeing on its hash. This
        // is allowed to share, and not allowed to contradict.
        let shared = good + "\nfile     copy.dll  win64  tier0_s64.dll  \(String(repeating: "b", count: 64))"
        #expect(throws: StepFailure.self) { try parse(shared) }
        #expect(throws: Never.self) {
            try parse(good + "\nfile     copy.dll  win64  tier0_s64.dll  \(hash)")
        }

        // A bundle row short a field, with a bad hash, and declared twice. Only one
        // bundle can be installed, so a second row is a mistake rather than a choice.
        let bundleRow = "bundle   appdmg_osx.zip.cc  \(hash)  SteamMacBootstrapper.tar.gz  Steam.app"
        #expect(throws: StepFailure.self) {
            try parse(good + "\nbundle   appdmg_osx.zip.cc  \(hash)  SteamMacBootstrapper.tar.gz")
        }
        #expect(throws: StepFailure.self) {
            try parse(good + "\n" + bundleRow.replacingOccurrences(of: hash, with: "aa"))
        }
        #expect(throws: StepFailure.self) { try parse(good + "\n" + bundleRow + "\n" + bundleRow) }
        #expect(throws: Never.self) { try parse(good + "\n" + bundleRow) }
    }
}
