import Foundation
import Testing

@testable import NotProtonApp

@Suite("Wine runtime")
struct WineRuntimeTests {

    @Test("Every supported build is a CrossOver build")
    func supportedBuildsAreCrossOver() {
        #expect(!SupportedRunners.all.isEmpty)
        #expect(SupportedRunners.all.allSatisfy { $0.runtime == .crossover })
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
}
