import CryptoKit
import Foundation
import HighballKit
import Testing

@testable import HighballEnvCore

@Suite("Engine install through HighballKit")
struct EngineInstallTests {

    struct Fixture {
        let work: URL
        let home: URL
        let manifest: URL
    }

    // A one-component engine whose archive is a local file, so nothing touches the network
    private func fixture(sha: String? = nil) throws -> Fixture {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appending(path: "hb-install-\(UUID().uuidString)")
        let payload = work.appending(path: "payload/dxmt/wine/x86_64-windows")
        try fm.createDirectory(at: payload, withIntermediateDirectories: true)
        try Data("dll".utf8).write(to: payload.appending(path: "d3d11.dll"))
        let archive = work.appending(path: "dxmt.tar.xz")
        let tar = Process()
        tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tar.arguments = ["-cJf", archive.path, "-C", work.appending(path: "payload").path, "dxmt"]
        try tar.run()
        tar.waitUntilExit()
        let digest = SHA256.hash(data: try Data(contentsOf: archive)).map { String(format: "%02x", $0) }.joined()
        let manifest: [String: Any] = [
            "id": "x64-test-r1", "displayName": "Test engine", "arch": "x86_64", "minMacOS": "14.0",
            "components": ["dxmt": [
                "kind": "renderer", "url": archive.absoluteString, "sha256": sha ?? digest,
                "extract": ["subpath": "dxmt/wine", "into": "renderers/dxmt/wine"],
            ]],
        ]
        let manifestURL = work.appending(path: "x64-test-r1.json")
        try JSONSerialization.data(withJSONObject: manifest).write(to: manifestURL)
        return Fixture(work: work, home: work.appending(path: "Highball"), manifest: manifestURL)
    }

    private func installedManifest(_ f: Fixture) throws -> EngineManifest {
        try EngineManifest.load(from: f.home.appending(path: "engines/x64-test-r1/manifest.json"))
    }

    @Test("The engine lands in Highball's folder without D3DMetal's licence unless the user accepted it")
    func installsWithoutLicence() async throws {
        let f = try fixture()
        let id = try await EngineInstall.install(manifest: f.manifest, acceptD3DMetal: false,
                                                 paths: HighballPaths(home: f.home)) { _ in }
        #expect(id == "x64-test-r1")
        #expect(FileManager.default.fileExists(
            atPath: f.home.appending(path: "engines/x64-test-r1/renderers/dxmt/wine/x86_64-windows/d3d11.dll").path))
        #expect((try installedManifest(f).acceptedLicenses ?? []).isEmpty)
    }

    @Test("Accepting in the download sheet records Apple's licence on the engine")
    func installsWithLicence() async throws {
        let f = try fixture()
        _ = try await EngineInstall.install(manifest: f.manifest, acceptD3DMetal: true,
                                            paths: HighballPaths(home: f.home)) { _ in }
        #expect(try installedManifest(f).acceptedLicenses == [EngineInstall.d3dmetalLicence])
    }

    @Test("A download that does not match Highball's checksum installs nothing")
    func checksumMismatch() async throws {
        let f = try fixture(sha: String(repeating: "0", count: 64))
        await #expect(throws: (any Error).self) {
            _ = try await EngineInstall.install(manifest: f.manifest, acceptD3DMetal: false,
                                                paths: HighballPaths(home: f.home)) { _ in }
        }
        #expect(!FileManager.default.fileExists(atPath: f.home.appending(path: "engines/x64-test-r1").path))
    }

    @Test("Enable D3DMetal later adds the licence to an installed engine")
    func acceptLater() async throws {
        let f = try fixture()
        let paths = HighballPaths(home: f.home)
        _ = try await EngineInstall.install(manifest: f.manifest, acceptD3DMetal: false, paths: paths) { _ in }
        try EngineInstall.accept(engineID: "x64-test-r1", paths: paths)
        #expect(try installedManifest(f).acceptedLicenses == [EngineInstall.d3dmetalLicence])
    }

    @Test("Available renderers follow Highball's rule: shipped folders, D3DMetal only with the licence")
    func availableRenderers() async throws {
        let f = try fixture()
        let paths = HighballPaths(home: f.home)
        _ = try await EngineInstall.install(manifest: f.manifest, acceptD3DMetal: false, paths: paths) { _ in }
        let d3dmetal = f.home.appending(path: "engines/x64-test-r1/frameworks/renderer/d3dmetal/wine")
        try FileManager.default.createDirectory(at: d3dmetal, withIntermediateDirectories: true)
        #expect(try EngineRenderers.available(engineID: "x64-test-r1", paths: paths) == ["wined3d", "dxmt"])
        try EngineInstall.accept(engineID: "x64-test-r1", paths: paths)
        #expect(try EngineRenderers.available(engineID: "x64-test-r1", paths: paths) == ["wined3d", "dxmt", "d3dmetal"])
    }

    @Test("Progress is reported once per percent, and always at the end")
    func throttledProgress() {
        let throttle = EngineInstall.ProgressThrottle()
        let total: Int64 = 400 << 20
        let lines = stride(from: Int64(0), through: total, by: 1 << 20).compactMap {
            throttle.line(component: "wine", got: $0, total: total)
        }
        #expect(lines.first == "progress wine 0 \(total)")
        #expect(lines.last == "progress wine \(total) \(total)")
        #expect(lines.count <= 102)
    }
}
