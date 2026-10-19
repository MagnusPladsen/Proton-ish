import Foundation
import Testing

@testable import NotProtonApp

@Suite("Engine guidance")
struct EngineGuidanceTests {

    private func build(_ id: String) -> RunnerBuild {
        RunnerBuild(
            bundleVersion: id, releaseVersion: id, flavor: nil, loaderSHA256: "", cleanNtdll: [:], patchedNtdll: [:],
            tools: [CompatTool(name: "protonish-highball-\(id)", flavor: .rosetta, display: "Highball \(id)")],
            runtime: .highball
        )
    }

    private let older = "x64-crossover26.3-r19"
    private let newer = "x64-crossover26.3-r25"

    @Test("The engine Steam's config names is the default")
    func steamDefault() {
        let role = EngineGuidance.role(build: build(older), newest: build(newer), request: nil,
                                       steamDefault: "protonish-highball-\(older)")
        #expect(role == .steamDefault)
    }

    @Test("A requested engine Steam has not applied yet is pending")
    func pendingDefault() {
        let role = EngineGuidance.role(build: build(newer), newest: build(newer),
                                       request: "protonish-highball-\(newer)", steamDefault: "protonish-highball-\(older)")
        #expect(role == .pendingDefault)
    }

    @Test("An engine Steam still names is not the default once another one was requested")
    func replacedDefault() {
        let role = EngineGuidance.role(build: build(older), newest: build(newer),
                                       request: "protonish-highball-\(newer)", steamDefault: "protonish-highball-\(older)")
        #expect(role == .plain)
    }

    @Test("A cleared request leaves the engine Steam still names as plain")
    func clearedRequest() {
        let role = EngineGuidance.role(build: build(newer), newest: build(newer), request: "",
                                       steamDefault: "protonish-highball-\(newer)")
        #expect(role == .newest)
    }

    @Test("The newest engine is pointed out when it is not the default")
    func newestEngine() {
        let role = EngineGuidance.role(build: build(newer), newest: build(newer), request: nil, steamDefault: "proton_9")
        #expect(role == .newest)
    }

    @Test("An older engine that is not the default gets no guidance")
    func olderEngine() {
        let role = EngineGuidance.role(build: build(older), newest: build(newer), request: nil, steamDefault: nil)
        #expect(role == .plain)
    }
}
