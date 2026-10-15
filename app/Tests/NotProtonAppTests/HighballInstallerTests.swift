import Foundation
import Testing

@testable import NotProtonApp

@Suite("Highball engine download")
struct HighballInstallerTests {

    private func helper(_ script: String, in work: URL) throws -> URL {
        let url = work.appending(path: "highball-env")
        try Data("#!/bin/sh\n\(script)\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path(percentEncoded: false))
        return url
    }

    @Test("Apple's licence is passed only when the user accepted it")
    func licenceFlagOnlyWhenAccepted() {
        let manifest = URL(filePath: "/payload/highball-engines/x64-crossover26.3-r19.json")
        #expect(!HighballInstaller.arguments(manifest: manifest, acceptD3DMetal: false).contains("--accept-d3dmetal"))
        #expect(HighballInstaller.arguments(manifest: manifest, acceptD3DMetal: true)
                == ["install", "--manifest", manifest.path(percentEncoded: false), "--accept-d3dmetal"])
    }

    @Test("Progress lines become status text; other lines do not")
    func progressLabels() {
        #expect(HighballInstaller.label(forLine: "progress wine 1048576 2097152")?.contains("wine") == true)
        #expect(HighballInstaller.label(forLine: "installed x64-crossover26.3-r19") == nil)
        #expect(HighballInstaller.label(forLine: "progress wine many 2") == nil)
    }

    @Test("The download size is the sum of the manifest's components")
    func downloadSize() throws {
        let work = try scratchDirectory("hb-size")
        defer { try? FileManager.default.removeItem(at: work) }
        let manifest = work.appending(path: "m.json")
        try Data(#"{"components":{"wine":{"size":300},"dxmt":{"size":20},"winetricks":{}}}"#.utf8).write(to: manifest)
        #expect(HighballInstaller.downloadBytes(manifest: manifest) == 320)
    }

    @Test("A successful helper run reports its progress")
    func successfulRun() async throws {
        let work = try scratchDirectory("hb-run")
        defer { try? FileManager.default.removeItem(at: work) }
        let tool = try helper("echo 'progress wine 1048576 2097152'\necho 'installed x64-test'", in: work)
        let labels = LabelBox()
        try await HighballInstaller.run(helper: tool, arguments: ["install"]) { labels.add($0) }
        #expect(labels.all.count == 1)
    }

    @Test("A failing helper's own error line becomes the failure")
    func failingRun() async throws {
        let work = try scratchDirectory("hb-fail")
        defer { try? FileManager.default.removeItem(at: work) }
        let tool = try helper("echo '# error: checksum mismatch for wine'\nexit 1", in: work)
        do {
            try await HighballInstaller.run(helper: tool, arguments: ["install"]) { _ in }
            Issue.record("the run should have failed")
        } catch let failure as StepFailure {
            #expect(failure.detail == "checksum mismatch for wine")
        }
    }

    @Test("An engine knows whether Apple's licence was accepted for it")
    func licenceState() throws {
        let work = try scratchDirectory("hb-licence")
        defer { try? FileManager.default.removeItem(at: work) }
        for (name, accepted) in [("with", ["apple-gptk-license-2023-08-17"]), ("without", [])] {
            let dir = work.appending(path: name)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let manifest = ["id": name, "displayName": name, "acceptedLicenses": accepted] as [String: Any]
            try JSONSerialization.data(withJSONObject: manifest).write(to: dir.appending(path: "manifest.json"))
        }
        #expect(HighballSource.inspect(work.appending(path: "with"))?.d3dmetalAccepted == true)
        #expect(HighballSource.inspect(work.appending(path: "without"))?.d3dmetalAccepted == false)
    }
}

private final class LabelBox: @unchecked Sendable {
    private let lock = NSLock()
    private var labels: [String] = []
    func add(_ label: String) { lock.lock(); labels.append(label); lock.unlock() }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return labels }
}
