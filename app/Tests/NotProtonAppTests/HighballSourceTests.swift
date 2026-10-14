import Foundation
import Testing

@testable import NotProtonApp

@Suite("Highball source")
struct HighballSourceTests {

    private func makeEngine(in home: URL, id: String, manifest: String?) throws {
        let directory = home.appending(path: "engines/\(id)")
        try FileManager.default.createDirectory(at: directory.appending(path: "engine/bin"), withIntermediateDirectories: true)
        try Data("not a real loader \(id)".utf8).write(to: directory.appending(path: "engine/bin/wine"))
        if let manifest {
            try Data(manifest.utf8).write(to: directory.appending(path: "manifest.json"))
        }
    }

    @Test("HIGHBALL_HOME wins, then config.json's home, then the default")
    func homeResolution() throws {
        let base = try scratchDirectory("hb-home")
        defer { try? FileManager.default.removeItem(at: base) }
        let fallback = base.appending(path: "Highball")
        try FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)

        #expect(HighballSource.home(environment: [:], defaultHome: fallback) == fallback)
        try Data(#"{"home": "/Volumes/Games/Highball"}"#.utf8).write(to: fallback.appending(path: "config.json"))
        #expect(HighballSource.home(environment: [:], defaultHome: fallback).path(percentEncoded: false)
            == "/Volumes/Games/Highball")
        #expect(HighballSource.home(environment: ["HIGHBALL_HOME": "/X"], defaultHome: fallback)
            .path(percentEncoded: false) == "/X")
    }

    @Test("An engine with an unknown loader is listed as unsupported, with its manifest name")
    func unknownEngineIsUnsupported() throws {
        let home = try scratchDirectory("hb-discover")
        defer { try? FileManager.default.removeItem(at: home) }
        try makeEngine(in: home, id: "x64-fake-r1", manifest: #"{"id": "x64-fake-r1", "displayName": "Fake Wine"}"#)

        let engines = HighballSource.discover(home: home)
        #expect(engines.map(\.id) == ["x64-fake-r1"])
        #expect(engines.first?.displayName == "Fake Wine")
        #expect(engines.first?.support == .unsupported)
        #expect(engines.first?.isUsable == false)
    }

    @Test("A directory without a manifest is not an engine")
    func noManifestSkipped() throws {
        let home = try scratchDirectory("hb-nomanifest")
        defer { try? FileManager.default.removeItem(at: home) }
        try makeEngine(in: home, id: "half-downloaded", manifest: nil)
        #expect(HighballSource.discover(home: home).isEmpty)
    }

    @Test("A manifest that is not JSON makes the engine unreadable")
    func brokenManifestUnreadable() throws {
        let home = try scratchDirectory("hb-broken")
        defer { try? FileManager.default.removeItem(at: home) }
        try makeEngine(in: home, id: "x64-broken-r1", manifest: "{ not json")
        #expect(HighballSource.discover(home: home).first?.support == .unreadable)
    }

    @Test("No Highball home means no engines")
    func missingHome() {
        #expect(HighballSource.discover(home: URL(filePath: "/nonexistent-\(UUID().uuidString)")).isEmpty)
    }
}
