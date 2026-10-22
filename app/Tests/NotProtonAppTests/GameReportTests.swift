import Foundation
import Testing

@testable import NotProtonApp

@Suite("Game report")
struct GameReportTests {

    private func report(renderer: String? = "dxmt", kitVersion: String? = "0.10.22", title: String = "Emberward")
        -> GameReport
    {
        GameReport(
            title: title, appID: "2459550", engine: "x64-crossover26.3-r27", renderer: renderer,
            kitVersion: kitVersion, appVersion: "1.0.5", chip: "Apple M1 Pro", macOS: "26.6.2")
    }

    private func fields(_ url: URL) -> [String: String] {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { _, last in last })
    }

    private func prefix() -> WinePrefix {
        WinePrefix(
            appID: "2459550", name: "Emberward",
            library: SteamLibrary(root: URL(filePath: "/Users/tester/Library/Application Support/Steam")),
            lastUsed: nil)
    }

    private func tempLog(_ text: String) throws -> URL {
        let file = FileManager.default.temporaryDirectory.appending(path: "game-report-\(UUID().uuidString).log")
        try Data(text.utf8).write(to: file)
        return file
    }

    @Test("The form gets every fact by its field id")
    func everyFact() {
        let url = report().url
        let query = fields(url)
        #expect(url.host() == "github.com")
        #expect(url.path() == "/gauthierpiarrette/highball-db/issues/new")
        #expect(query["template"] == "report.yml")
        #expect(query["title"] == "Emberward")
        #expect(query["steam_appid"] == "2459550")
        #expect(query["engine"] == "x64-crossover26.3-r27")
        #expect(query["renderer"] == "dxmt")
        #expect(query["chip"] == "Apple M1 Pro")
        #expect(query["macos"] == "26.6.2")
        #expect(query["version"] == "Proton-ish 1.0.5, HighballKit 0.10.22")
        #expect(query["session"] == "Played through Proton-ish (macOS Steam), Highball engine x64-crossover26.3-r27.")
    }

    @Test("Rating, issues, settings and notes stay the player's")
    func playerFieldsEmpty() {
        let query = fields(report().url)
        for key in ["rating", "issues", "settings", "notes"] {
            #expect(query[key] == nil, "\(key) is pre-filled")
        }
    }

    @Test("Without a renderer or HighballKit version those are left out or shortened")
    func missingFacts() {
        let query = fields(report(renderer: nil, kitVersion: nil).url)
        #expect(query["renderer"] == nil)
        #expect(query["version"] == "Proton-ish 1.0.5")
    }

    @Test("A title keeps its punctuation")
    func titlePunctuation() {
        #expect(fields(report(title: "Café ☕ & Co #2").url)["title"] == "Café ☕ & Co #2")
    }

    @Test("A plus sign is not read as a space by the form")
    func titlePlus() {
        let url = report(title: "Ys I + II").url
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery ?? ""
        #expect(!query.contains("+"))
        #expect(fields(url)["title"] == "Ys I + II")
    }

    @Test("The last launch's renderer and HighballKit win")
    func lastLaunchWins() {
        let log = """
            highball-env: highball-env HighballKit 0.10.15
            highball-env: note: renderer dxvk
            steam exited
            highball-env: highball-env HighballKit 0.10.22
            highball-env: note: renderer dxmt
            """
        #expect(GameReport.lastLaunch(inLog: log) == GameReport.LaunchFacts(renderer: "dxmt", kitVersion: "0.10.22"))
    }

    @Test("A renderer the form does not offer is left out")
    func unknownRenderer() {
        #expect(GameReport.lastLaunch(inLog: "highball-env: note: renderer metalfx\n").renderer == nil)
    }

    @Test("Only Highball engine ids count")
    func engineIDs() {
        for build in ["x64-crossover26.3-r27", "x64-crossover26.3-r12", "arm64-wine11.18-r6"] {
            #expect(GameReport.isHighballEngine(build), "\(build)")
        }
        for build in ["26.3.0.41073", "99.0.0.12345", ""] {
            #expect(!GameReport.isHighballEngine(build), "\(build)")
        }
    }

    @Test("A CrossOver prefix has no report, whatever its log says")
    func crossOverPrefix() throws {
        let log = try tempLog("highball-env: highball-env HighballKit 0.10.22\nhighball-env: note: renderer dxmt\n")
        defer { try? FileManager.default.removeItem(at: log) }
        let made = GameReport.make(
            for: prefix(), record: PrefixBuildRecord(build: "26.3.0.41073", display: "CrossOver 26.3"),
            appVersion: "1.0.5", log: log)
        #expect(made == nil)
    }

    @Test("A Highball engine no longer listed is still reported")
    func retiredEngine() throws {
        let log = try tempLog("highball-env: note: renderer dxvk\n")
        defer { try? FileManager.default.removeItem(at: log) }
        let made = GameReport.make(
            for: prefix(), record: PrefixBuildRecord(build: "x64-crossover26.3-r12", display: nil),
            appVersion: "1.0.5", chip: "Apple M2", macOS: "15.6", log: log)
        #expect(made?.engine == "x64-crossover26.3-r12")
        #expect(made?.renderer == "dxvk")
        #expect(made?.title == "Emberward")
        #expect(made?.appID == "2459550")
    }

    @Test("A missing log still gives a report")
    func missingLog() {
        let made = GameReport.make(
            for: prefix(), record: PrefixBuildRecord(build: "x64-crossover26.3-r27", display: nil),
            appVersion: "1.0.5",
            log: FileManager.default.temporaryDirectory.appending(path: "no-such-\(UUID().uuidString).log"))
        #expect(made != nil)
        #expect(made?.renderer == nil)
        #expect(made?.kitVersion == nil)
    }

    @Test("Only the end of a long log is read")
    func longLog() throws {
        let filler = String(repeating: "wine: some chatter that fills the log\n", count: 1 << 16)  // ~2.4 MiB
        let record = PrefixBuildRecord(build: "x64-crossover26.3-r27", display: nil)

        let recent = try tempLog(filler + filler + "highball-env: note: renderer d3dmetal\n")
        defer { try? FileManager.default.removeItem(at: recent) }
        #expect(GameReport.make(for: prefix(), record: record, appVersion: "1.0.5", log: recent)?.renderer == "d3dmetal")

        let old = try tempLog("highball-env: note: renderer d3dmetal\n" + filler)
        defer { try? FileManager.default.removeItem(at: old) }
        #expect(GameReport.make(for: prefix(), record: record, appVersion: "1.0.5", log: old)?.renderer == nil)
    }

    @Test("The Mac's facts are filled in")
    func machineFacts() {
        #expect(!GameReport.Machine.chip.isEmpty)
        #expect(GameReport.Machine.macOS.wholeMatch(of: /\d+\.\d+(\.\d+)?/) != nil)
    }
}
