import Foundation
import Testing

@testable import NotProtonApp

@Suite("Rosetta 2")
struct RosettaTests {

    private func runtime(present: Bool) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "rosetta-\(UUID().uuidString)/oah")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // The folder alone, as a Mac with only RosettaLinux has it, is not Rosetta 2
        try Data("linux".utf8).write(to: dir.appending(path: "RosettaLinux"))
        let file = dir.appending(path: "libRosettaRuntime")
        if present { try Data("runtime".utf8).write(to: file) }
        return file
    }

    @Test("Apple silicon without the Rosetta runtime is missing it, even with the oah folder")
    func missingOnAppleSilicon() throws {
        let file = try runtime(present: false)
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent().deletingLastPathComponent()) }
        #expect(Rosetta.isMissing(appleSilicon: true, runtime: file))
    }

    @Test("With the runtime installed nothing is missing")
    func installed() throws {
        let file = try runtime(present: true)
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent().deletingLastPathComponent()) }
        #expect(!Rosetta.isMissing(appleSilicon: true, runtime: file))
    }

    @Test("An Intel Mac never needs Rosetta 2")
    func intel() throws {
        let file = try runtime(present: false)
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent().deletingLastPathComponent()) }
        #expect(!Rosetta.isMissing(appleSilicon: false, runtime: file))
    }

    @Test("The command is the one the run script names")
    func sameCommandAsTheRunScript() throws {
        let repo = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let script = try String(contentsOf: repo.appending(path: "dylib/feats/compat_run.sh"), encoding: .utf8)
        #expect(script.contains(Rosetta.installCommand))
    }
}
