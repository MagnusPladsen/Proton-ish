import Foundation
import Testing

@testable import NotProtonApp

@Suite("Signed requirement")
struct SignedRequirementTests {

    private let ours = "identifier \"com.valvesoftware.steam\" and certificate leaf = H\"99f018fc\""
    private let valve = "identifier \"com.valvesoftware.steam\" and anchor apple generic"

    @Test("A signature Steam already carried needs no reset")
    func unchangedSignature() {
        #expect(!SignedRequirement.needsReset(prior: ours, recorded: nil, signed: ours))
    }

    @Test("A signature recorded at the last signing needs no reset, whatever Steam carried before")
    func recordedSignature() {
        #expect(!SignedRequirement.needsReset(prior: valve, recorded: ours, signed: ours))
    }

    @Test("A signature nobody has seen resets the grant")
    func newSignature() {
        #expect(SignedRequirement.needsReset(prior: valve, recorded: "cdhash H\"01\"", signed: ours))
    }

    @Test("A signature that cannot be read resets the grant")
    func unknownSignature() {
        #expect(SignedRequirement.needsReset(prior: ours, recorded: ours, signed: nil))
    }

    @Test("The recorded requirement reads back; no file is no record")
    func recordRoundTrip() throws {
        let work = try scratchDirectory("signed-requirement")
        defer { try? FileManager.default.removeItem(at: work) }
        let file = work.appending(path: "signed-requirement")
        #expect(SignedRequirement.read(at: file) == nil)
        try SignedRequirement.record(ours, at: file)
        #expect(SignedRequirement.read(at: file) == ours)
    }
}
