import Foundation
import Testing

@testable import NotProtonApp

@Suite("Game fixes verified on other engines")
struct OtherEngineFixesTests {

    @Test("Without the file the switch is on")
    func missingFileIsOn() throws {
        let work = try scratchDirectory("other-engine-fixes")
        defer { try? FileManager.default.removeItem(at: work) }
        #expect(OtherEngineFixes.isOn(at: work.appending(path: "recipe-other-engines")))
    }

    @Test("Turning the switch off writes skip")
    func offWritesSkip() throws {
        let work = try scratchDirectory("other-engine-fixes")
        defer { try? FileManager.default.removeItem(at: work) }
        let file = work.appending(path: "recipe-other-engines")
        try OtherEngineFixes.set(false, at: file)
        #expect(try String(contentsOf: file, encoding: .utf8) == "skip\n")
    }

    @Test("A file saying skip reads as off")
    func skipReadsOff() throws {
        let work = try scratchDirectory("other-engine-fixes")
        defer { try? FileManager.default.removeItem(at: work) }
        let file = work.appending(path: "recipe-other-engines")
        try OtherEngineFixes.set(false, at: file)
        #expect(!OtherEngineFixes.isOn(at: file))
    }

    @Test("Turning the switch back on reads as on")
    func onReadsOn() throws {
        let work = try scratchDirectory("other-engine-fixes")
        defer { try? FileManager.default.removeItem(at: work) }
        let file = work.appending(path: "recipe-other-engines")
        try OtherEngineFixes.set(false, at: file)
        try OtherEngineFixes.set(true, at: file)
        #expect(OtherEngineFixes.isOn(at: file))
    }
}
