import Foundation
import Testing

@testable import NotProtonApp

@Suite("Highball clone")
struct HighballCloneTests {

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    // A fake engines/<id> tree and a RunnerBuild pinned to its bytes
    private func makeEngine(in base: URL) throws -> (HighballEngine, RunnerBuild) {
        let directory = base.appending(path: "engines/x64-fake-r1")
        try write(#"{"id": "x64-fake-r1", "displayName": "Fake", "baseEnv": {"DYLD_FALLBACK_LIBRARY_PATH": "${frameworks}", "WINEDEBUG": "fixme-all", "bad key": "x"}}"#,
                  to: directory.appending(path: "manifest.json"))
        try write("highball loader", to: directory.appending(path: "engine/bin/wine"))
        try write("server", to: directory.appending(path: "engine/bin/wineserver"))
        try write("ntdll x64", to: directory.appending(path: "engine/lib/wine/x86_64-windows/ntdll.dll"))
        try write("ntdll x86", to: directory.appending(path: "engine/lib/wine/i386-windows/ntdll.dll"))
        try write("unix", to: directory.appending(path: "engine/lib/wine/x86_64-unix/ntdll.so"))
        try write("dylib", to: directory.appending(path: "frameworks/libX.dylib"))
        try write("dxmt", to: directory.appending(path: "renderers/dxmt/wine/x86_64-windows/d3d11.dll"))

        func hash(_ path: String) throws -> String {
            try #require(Digest.sha256IfPresent(directory.appending(path: path)))
        }
        let build = RunnerBuild(
            bundleVersion: "x64-fake-r1",
            releaseVersion: "r1",
            flavor: nil,
            loaderSHA256: try hash("engine/bin/wine"),
            cleanNtdll: [
                .x86_64Windows: try hash("engine/lib/wine/x86_64-windows/ntdll.dll"),
                .i386Windows: try hash("engine/lib/wine/i386-windows/ntdll.dll"),
            ],
            patchedNtdll: [:],
            runtime: .highball
        )
        let engine = HighballEngine(id: "x64-fake-r1", directory: directory, displayName: "Fake",
                                    support: .supported(build))
        return (engine, build)
    }

    @Test("The engine lands flat in highball-<id>/root with frameworks, renderers and runtime.env")
    func cloneIsFlat() throws {
        let base = try scratchDirectory("hb-clone")
        defer { try? FileManager.default.removeItem(at: base) }
        let runners = base.appending(path: "runners")
        try FileManager.default.createDirectory(at: runners, withIntermediateDirectories: true)
        let (engine, build) = try makeEngine(in: base)

        _ = try RunnerInstaller.clone(from: engine, runners: runners)

        let root = runners.appending(path: "highball-x64-fake-r1/root")
        for path in ["bin/wine", "bin/wineserver", "lib/wine/x86_64-windows/ntdll.dll", "lib/wine/x86_64-unix/ntdll.so",
                     "frameworks/libX.dylib", "renderers/dxmt/wine/x86_64-windows/d3d11.dll", "manifest.json"] {
            #expect(FileManager.default.fileExists(atPath: root.appending(path: path).path(percentEncoded: false)), "\(path)")
        }
        let env = try String(contentsOf: root.appending(path: "runtime.env"), encoding: .utf8)
        #expect(env == "DYLD_FALLBACK_LIBRARY_PATH=\(root.appending(path: "frameworks").path(percentEncoded: false))\nWINEDEBUG=fixme-all\n")
        #expect(RunnerInstaller.hasClone(forBuild: build.id, runners: runners))
        #expect(!FileManager.default.fileExists(atPath: runners.appending(path: ".highball-x64-fake-r1.new").path(percentEncoded: false)))
    }

    @Test("A changed loader no longer matches the build")
    func tamperedLoaderRefused() throws {
        let base = try scratchDirectory("hb-tamper")
        defer { try? FileManager.default.removeItem(at: base) }
        let runners = base.appending(path: "runners")
        try FileManager.default.createDirectory(at: runners, withIntermediateDirectories: true)
        let (engine, build) = try makeEngine(in: base)
        _ = try RunnerInstaller.clone(from: engine, runners: runners)

        let root = runners.appending(path: "highball-x64-fake-r1/root")
        try Data("someone else's loader".utf8).write(to: root.appending(path: "bin/wine"))
        #expect(throws: StepFailure.self) { try RunnerInstaller.verifyClone(build: build, root: root) }
    }

    @Test("An unsupported engine is not cloned")
    func unsupportedRefused() throws {
        let base = try scratchDirectory("hb-unsupported")
        defer { try? FileManager.default.removeItem(at: base) }
        let engine = HighballEngine(id: "x64-new-r99", directory: base, displayName: "New", support: .unsupported)
        #expect(throws: StepFailure.self) { try RunnerInstaller.clone(from: engine, runners: base) }
    }

    @Test("Setting up a Highball runner needs no CrossOver licence and lists a highball tool")
    func prepareHighballWithoutLicence() throws {
        let runners = try scratchDirectory("hb-prepare")
        defer { try? FileManager.default.removeItem(at: runners) }
        let build = try #require(SupportedRunners.build(id: "x64-crossover26.3-r19"))
        try FileManager.default.createDirectory(
            at: runners.appending(path: "highball-\(build.id)/root/lib/wine"), withIntermediateDirectories: true)

        _ = try RunnerSetup.prepare(
            build,
            runners: runners,
            bridge: runners.appending(path: "bridge"),
            toolList: runners.appending(path: "tools"),
            compatTools: runners.appending(path: "compatibilitytools.d"),
            runScript: {
                let script = runners.appending(path: "payload-run")
                try Data("#!/bin/sh\n".utf8).write(to: script)
                return script
            },
            verify: { _, _ in },
            stage: { _, _, _ in [] },
            patch: { _, _, _ in RunnerPatcher.Outcome() }
        )

        let tools = try String(contentsOf: runners.appending(path: "tools"), encoding: .utf8)
        #expect(tools.contains("protonish-highball-x64-crossover26.3-r19\tx64-crossover26.3-r19\trosetta\thighball\tHighball Wine 11 (r19)\n"))
    }
}
