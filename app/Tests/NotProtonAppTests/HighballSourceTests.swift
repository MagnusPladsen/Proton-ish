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

    @Test("An engine is only the pinned build when its manifest id matches too")
    func identityNeedsMatchingID() throws {
        let home = try scratchDirectory("hb-identity")
        defer { try? FileManager.default.removeItem(at: home) }
        let build = try #require(SupportedRunners.build(id: "x64-crossover26.3-r19"))
        // Another revision can ship the same launcher bytes as r19
        func engine(_ id: String) throws -> HighballEngine? {
            let directory = home.appending(path: "engines/\(id)")
            try FileManager.default.createDirectory(at: directory.appending(path: "engine/bin"), withIntermediateDirectories: true)
            try Data(#"{"id": "\#(id)"}"#.utf8).write(to: directory.appending(path: "manifest.json"))
            let fixture = FileManager.default.temporaryDirectory.appending(path: "hb-launcher-\(UUID().uuidString)")
            try Data(contentsOf: try #require(Self.r19Launcher)).write(to: fixture)
            try FileManager.default.moveItem(at: fixture, to: directory.appending(path: "engine/bin/wine"))
            return HighballSource.inspect(directory)
        }
        guard Self.r19Launcher != nil else { return }
        #expect(try engine("x64-crossover26.3-r19")?.support == .supported(build))
        #expect(try engine("x64-crossover26.3-r18")?.support == .unsupported)
    }

    @Test("Revisions that share r25's launcher are the build their manifest names")
    func sharedLauncherNamesTheBuild() throws {
        let home = try scratchDirectory("hb-shared-launcher")
        defer { try? FileManager.default.removeItem(at: home) }
        guard let launcher = Self.r25Launcher else { return }
        for id in ["x64-crossover26.3-r25", "x64-crossover26.3-r26", "x64-crossover26.3-r27"] {
            let directory = home.appending(path: "engines/\(id)")
            try FileManager.default.createDirectory(at: directory.appending(path: "engine/bin"), withIntermediateDirectories: true)
            try Data(#"{"id": "\#(id)"}"#.utf8).write(to: directory.appending(path: "manifest.json"))
            try FileManager.default.copyItem(at: launcher, to: directory.appending(path: "engine/bin/wine"))
            #expect(HighballSource.inspect(directory)?.support == .supported(try #require(SupportedRunners.build(id: id))))
        }
    }

    // The real r25 launcher, when a Highball install has it
    static var r25Launcher: URL? {
        let url = HighballSource.home().appending(path: "engines/x64-crossover26.3-r25/engine/bin/wine")
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? url : nil
    }

    // The real r19 launcher, when the scratch fixture or a Highball install has it
    static var r19Launcher: URL? {
        let repo = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return [repo.appending(path: "scratch/hb-r19/engine/bin/wine"),
                HighballSource.home().appending(path: "engines/x64-crossover26.3-r19/engine/bin/wine")]
            .first { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
    }

    @Test("No Highball home means no engines")
    func missingHome() {
        #expect(HighballSource.discover(home: URL(filePath: "/nonexistent-\(UUID().uuidString)")).isEmpty)
    }
}

@Suite("Highball engine order")
struct HighballEngineOrderTests {
    private func engine(_ id: String, _ support: HighballSupport) -> HighballEngine {
        HighballEngine(id: id, directory: URL(filePath: "/H/engines/\(id)"), displayName: id, support: support)
    }

    @Test("Usable engines come first, then newest revision first within a line")
    func usableAndNewestFirst() throws {
        let r19 = engine("x64-crossover26.3-r19", .supported(try #require(SupportedRunners.build(id: "x64-crossover26.3-r19"))))
        let r25 = engine("x64-crossover26.3-r25", .supported(try #require(SupportedRunners.build(id: "x64-crossover26.3-r25"))))
        let r9 = engine("x64-crossover26.3-r9", .unsupported)
        let sikarugir = engine("x64-sikarugir10.0_6-r21", .unsupported)
        let listed = [sikarugir, r9, r19, r25].sorted(by: HighballSource.isListedBefore).map(\.id)
        #expect(listed == ["x64-crossover26.3-r25", "x64-crossover26.3-r19", "x64-crossover26.3-r9", "x64-sikarugir10.0_6-r21"])
    }
}

@Suite("Highball notice")
struct HighballNoticeTests {

    private func engine(_ id: String, _ support: HighballSupport) -> HighballEngine {
        HighballEngine(id: id, directory: URL(filePath: "/H/engines/\(id)"), displayName: id, support: support)
    }

    @Test("Only Wine 10 engines asks for the Wine 11 engine")
    func onlyWine10() {
        let notice = SystemStatus.highballNotice(engines: [engine("x64-sikarugir10.0_6-r21", .unsupported)])
        #expect(notice?.contains("Wine 11") == true)
    }

    @Test("An unsupported Wine 11 engine is named")
    func unsupportedWine11() {
        let notice = SystemStatus.highballNotice(engines: [engine("x64-crossover26.3-r99", .unsupported)])
        #expect(notice?.contains("x64-crossover26.3-r99") == true)
    }

    @Test("A supported engine needs no notice")
    func supported() throws {
        let build = try #require(SupportedRunners.build(id: "x64-crossover26.3-r19"))
        #expect(SystemStatus.highballNotice(engines: [engine("x64-crossover26.3-r19", .supported(build)),
                                                      engine("x64-sikarugir10.0_6-r21", .unsupported)]) == nil)
    }

    @Test("No engines needs no notice")
    func none() {
        #expect(SystemStatus.highballNotice(engines: []) == nil)
    }
}

@Suite("Highball rows")
struct HighballRowTests {

    @Test("A Highball copy is not set up, ready, or in need of repair")
    func copyState() throws {
        let build = try #require(SupportedRunners.build(id: "x64-crossover26.3-r19"))
        #expect(SystemStatus.highballCopy(build.id, installed: [], runner: .none) == .notSetUp)
        #expect(SystemStatus.highballCopy(build.id, installed: [build], runner: .ready(builds: [build.id])) == .ready)
        #expect(SystemStatus.highballCopy(build.id, installed: [build],
                                          runner: .unpatched(builds: [build.id], problems: ["x"])) == .needsRepair)
    }

    @Test("Orphaned Highball copies are found by their directory, CrossOver ones are not")
    func orphans() throws {
        let runners = try scratchDirectory("hb-orphans")
        defer { try? FileManager.default.removeItem(at: runners) }
        try FileManager.default.createDirectory(at: runners.appending(path: "highball-x64-old-r1"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: runners.appending(path: "crossover-1.2.3"), withIntermediateDirectories: true)
        #expect(SystemStatus.highballOrphans(["x64-old-r1", "1.2.3"], runners: runners) == ["x64-old-r1"])
    }
}
