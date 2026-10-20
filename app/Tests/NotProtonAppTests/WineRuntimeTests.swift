import Foundation
import Testing

@testable import NotProtonApp

@Suite("Wine runtime")
struct WineRuntimeTests {

    @Test("Every supported build names a known runtime")
    func supportedBuildsHaveRuntimes() {
        #expect(SupportedRunners.all.allSatisfy { RuntimeKind.allCases.contains($0.runtime) })
    }

    @Test("A rebuild keeps the runtime of the build it belongs to")
    func rebuildKeepsRuntime() throws {
        let build = try #require(SupportedRunners.all.first { !$0.rebuilds.isEmpty })
        let rebuild = try #require(build.rebuilds.first)
        #expect(build.matching(loaderSHA256: rebuild.loaderSHA256)?.runtime == build.runtime)
    }

    @Test("The runtime's raw value is the runner directory prefix")
    func rawValueIsDirectoryPrefix() {
        #expect(RuntimeKind.crossover.rawValue == "crossover")
    }

    @Test("A runner clone lives under <runtime>-<build>/root")
    func clonedRootIsGeneric() {
        let runners = URL(filePath: "/R")
        #expect(SupportPaths.runnerRoot(forBuild: "26.3.0.39832", runners: runners).path(percentEncoded: false)
            == "/R/crossover-26.3.0.39832")
        #expect(SupportPaths.clonedRoot(forBuild: "26.3.0.39832", runners: runners).path(percentEncoded: false)
            == "/R/crossover-26.3.0.39832/root")
    }

    @Test("Cloned builds are found under every runtime prefix, and nothing else is")
    func clonedBuildsAcrossRuntimes() throws {
        let runners = FileManager.default.temporaryDirectory.appending(path: "np-rt-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: runners) }
        for name in ["crossover-26.3.0.39832", "crossover-27.0.0.40921-fex", "other-1", ".crossover-1.new"] {
            try FileManager.default.createDirectory(at: runners.appending(path: name), withIntermediateDirectories: true)
        }
        #expect(RunnerStore.clonedBuilds(in: runners) == ["26.3.0.39832", "27.0.0.40921-fex"])
    }

    @Test("CrossOver's loader is the x86_64 unix wine binary")
    func crossOverLoader() {
        let root = URL(filePath: "/R/root")
        #expect(RuntimeKind.crossover.runtime.unixLoader(inRoot: root).path(percentEncoded: false)
            == "/R/root/lib/wine/x86_64-unix/wine")
        #expect(CrossOverSource.unixLoader(inRoot: root) == RuntimeKind.crossover.runtime.unixLoader(inRoot: root))
    }

    @Test("CrossOver's base environment sets CX_ROOT and CX_HOME")
    func crossOverEnvironment() {
        let env = RuntimeKind.crossover.runtime.baseEnvironment(root: URL(filePath: "/R/root"))
        #expect(env["CX_ROOT"] == "/R/root")
        #expect(env["CX_HOME"]?.hasSuffix("/Library/Application Support/CrossOver") == true)
    }

    @Test("PrefixTools' layout is the runtime's layout")
    func layoutDelegates() {
        let root = URL(filePath: "/R/root")
        for flavor in CompatTool.Flavor.allCases {
            let a = PrefixTools.layout(runner: root, flavor: flavor)
            let b = RuntimeKind.crossover.runtime.layout(root: root, flavor: flavor)
            #expect(a.loader == b.loader && a.server == b.server && a.unixDir == b.unixDir)
        }
    }

    @Test("The run script builds the runner root the same way the app does")
    func runScriptRootMatchesApp() throws {
        let repo = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let script = try String(contentsOf: repo.appending(path: "dylib/feats/compat_run.sh"), encoding: .utf8)
        #expect(script.contains("CX_ROOT=\"$np_support/runners/$np_runtime-$np_build/\(SupportPaths.clonedFolder)\""))
        let root = SupportPaths.clonedRoot(forBuild: "26.3.0.39832", runners: URL(filePath: "/S/runners"))
        #expect(root.path(percentEncoded: false) == "/S/runners/\(RuntimeKind.crossover.rawValue)-26.3.0.39832/\(SupportPaths.clonedFolder)")
    }

    @Test("Highball runs its x86_64-unix loader and keeps wineserver in bin")
    func highballLayout() {
        let root = URL(filePath: "/R/root")
        let runtime = RuntimeKind.highball.runtime
        #expect(runtime.unixLoader(inRoot: root).path(percentEncoded: false) == "/R/root/bin/wine")
        let layout = runtime.layout(root: root, flavor: .fex)
        // Run the real loader directly, as for CrossOver; bin/wine is Highball's launcher
        #expect(layout.loader.path(percentEncoded: false) == "/R/root/lib/wine/x86_64-unix/wine")
        #expect(layout.server.path(percentEncoded: false) == "/R/root/bin/wineserver")
        #expect(layout.unixDir.path(percentEncoded: false) == "/R/root/lib/wine/x86_64-unix")
        #expect(runtime.accessStatus(root: root).licensed)
    }

    @Test("runtime.env keeps only plain KEY=VALUE lines")
    func envFileParsing() {
        let parsed = HighballRuntime.parseEnvFile("""
        DYLD_FALLBACK_LIBRARY_PATH=/R/root/frameworks
        WINEDEBUG=fixme-all
        # comment
        lower=no
        BAD KEY=no
        $(touch /tmp/x)=no
        GST_PLUGIN_PATH=/a b/c
        """)
        #expect(parsed == ["DYLD_FALLBACK_LIBRARY_PATH": "/R/root/frameworks", "WINEDEBUG": "fixme-all",
                           "GST_PLUGIN_PATH": "/a b/c"])
    }

    @Test("A clone's runtime comes from its directory, even for a build no longer supported")
    func runtimeFromDirectory() throws {
        let runners = FileManager.default.temporaryDirectory.appending(path: "np-rt-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: runners) }
        try FileManager.default.createDirectory(at: runners.appending(path: "highball-x64-old-r1/root/lib/wine"),
                                                withIntermediateDirectories: true)
        #expect(SupportPaths.runtime(forBuild: "x64-old-r1", runners: runners) == .highball)
        #expect(SupportPaths.runnerRoot(forBuild: "x64-old-r1", runners: runners).lastPathComponent == "highball-x64-old-r1")
        #expect(RunnerStore.clonedBuilds(in: runners) == ["x64-old-r1"])
        #expect(RunnerInstaller.hasClone(forBuild: "x64-old-r1", runners: runners))
    }

    @Test("Highball r19 is a supported Rosetta build with one tool")
    func highballR19Supported() throws {
        let build = try #require(SupportedRunners.build(id: "x64-crossover26.3-r19"))
        #expect(build.runtime == .highball)
        #expect(build.tools.map(\.name) == ["protonish-highball-x64-crossover26.3-r19"])
        #expect(build.tools.allSatisfy { $0.flavor == .rosetta })
        #expect(NtdllPatcher.byBuild["x64-crossover26.3-r19"]?.count == 2)
    }

    @Test("Highball r25 is a supported Rosetta build with one tool")
    func highballR25Supported() throws {
        let build = try #require(SupportedRunners.build(id: "x64-crossover26.3-r25"))
        #expect(build.runtime == .highball)
        #expect(build.tools.map(\.name) == ["protonish-highball-x64-crossover26.3-r25"])
        #expect(build.tools.allSatisfy { $0.flavor == .rosetta })
        #expect(NtdllPatcher.byBuild["x64-crossover26.3-r25"]?.count == 2)
    }

    @Test("Highball r26 and r27 carry r25's Wine build: same loader and ntdll hashes, their own ids and tools")
    func highballR26R27Supported() throws {
        let r25 = try #require(SupportedRunners.build(id: "x64-crossover26.3-r25"))
        for id in ["x64-crossover26.3-r26", "x64-crossover26.3-r27"] {
            let build = try #require(SupportedRunners.build(id: id))
            #expect(build.runtime == .highball)
            #expect(build.loaderSHA256 == r25.loaderSHA256)
            #expect(build.cleanNtdll == r25.cleanNtdll && build.patchedNtdll == r25.patchedNtdll)
            #expect(build.tools.map(\.name) == ["protonish-highball-\(id)"])
            #expect(NtdllPatcher.byBuild[id]?.map(\.payloadSHA256) == NtdllPatcher.byBuild["x64-crossover26.3-r25"]?.map(\.payloadSHA256))
        }
    }

    @Test("Highball r27 is the build offered for download, r26 needs macOS 27")
    func highballR27Offered() throws {
        #expect(HighballInstaller.build?.id == "x64-crossover26.3-r27")
    }

    // Runs when the r19 engine is on this Mac (Highball install or the plan's scratch fixture):
    // the app's own patcher must reproduce the pinned output byte for byte.
    @Test("The app patches Highball r19's ntdll to the pinned hashes")
    func highballR19PatchesToPin() throws {
        let repo = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let candidates = [
            repo.appending(path: "scratch/hb-r19/engine"),
            HighballSource.home().appending(path: "engines/x64-crossover26.3-r19/engine"),
        ]
        guard let root = candidates.first(where: {
            FileManager.default.fileExists(atPath: $0.appending(path: "lib/wine/x86_64-windows/ntdll.dll").path(percentEncoded: false))
        }) else { return }
        let build = try #require(SupportedRunners.build(id: "x64-crossover26.3-r19"))
        let out = try scratchDirectory("hb-patch")
        defer { try? FileManager.default.removeItem(at: out) }
        for patch in NtdllPatcher.patches(for: build) {
            let destination = out.appending(path: "\(patch.arch.rawValue).dll")
            let hash = try NtdllPatcher.write(patch, build: build,
                                              from: root.appending(path: "lib/wine/\(patch.arch.rawValue)/ntdll.dll"),
                                              to: destination)
            #expect(hash == build.patchedNtdll[patch.arch])
        }
    }

    @Test("A runner path names its runtime, and PrefixTools follows it")
    func prefixToolsFollowRunnerRuntime() throws {
        let highball = URL(filePath: "/S/runners/highball-x64-crossover26.3-r19/root")
        let crossover = URL(filePath: "/S/runners/crossover-26.3.0.39832/root")
        #expect(RuntimeKind.of(runner: highball) == .highball)
        #expect(RuntimeKind.of(runner: crossover) == .crossover)
        #expect(RuntimeKind.of(runner: URL(filePath: "/elsewhere/root")) == .crossover)

        #expect(PrefixTools.layout(runner: highball, flavor: .rosetta).loader.path(percentEncoded: false)
            == "/S/runners/highball-x64-crossover26.3-r19/root/lib/wine/x86_64-unix/wine")
        let prefix = WinePrefix(appID: "1", name: nil, library: SteamLibrary(root: URL(filePath: "/L")), lastUsed: nil)
        let env = PrefixTools.environment(prefix: prefix, runner: highball, flavor: .rosetta)
        #expect(env["WINEUSERNAME"] == "steamuser")
        #expect(env["WINELOADER"] == "/S/runners/highball-x64-crossover26.3-r19/root/lib/wine/x86_64-unix/wine")
        #expect(env["CX_ROOT"] == nil)
    }
}
