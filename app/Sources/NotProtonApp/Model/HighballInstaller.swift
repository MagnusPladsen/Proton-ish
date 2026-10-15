// Downloads Highball's engine with the bundled highball-env (Highball's own EngineStore), so a
// user needs no Highball app. Apple's D3DMetal licence is passed only when the user accepted it.

import Foundation

enum HighballInstaller {

    static let step = String(localized: "Download the Highball engine")

    // The newest supported Highball build, the one Proton-ish offers to download
    static var build: RunnerBuild? {
        SupportedRunners.all.last { $0.runtime == .highball }
    }

    static func manifest(in payload: InstallPayload.Located, build: RunnerBuild) -> URL {
        payload.highballEngines.appending(path: "\(build.bundleVersion).json")
    }

    static func licenceText(in payload: InstallPayload.Located) -> String {
        (try? String(contentsOf: payload.highballEngines.appending(path: "d3dmetal-license.txt"), encoding: .utf8)) ?? ""
    }

    // Sum of the component sizes Highball's manifest states
    static func downloadBytes(manifest: URL) -> Int64 {
        guard let data = try? Data(contentsOf: manifest),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let components = object["components"] as? [String: [String: Any]] else { return 0 }
        return components.values.reduce(0) { $0 + Int64(($1["size"] as? Int) ?? 0) }
    }

    static func arguments(manifest: URL, acceptD3DMetal: Bool) -> [String] {
        ["install", "--manifest", manifest.path(percentEncoded: false)] + (acceptD3DMetal ? ["--accept-d3dmetal"] : [])
    }

    // "progress wine 1048576 334866127" from highball-env becomes a status line
    static func label(forLine line: String) -> String? {
        let fields = line.split(separator: " ")
        guard fields.count == 4, fields[0] == "progress", let got = Int64(fields[2]), let total = Int64(fields[3]) else {
            return nil
        }
        let component = String(fields[1])
        let done = got.formatted(.byteCount(style: .file))
        guard total > 0 else { return String(localized: "Downloading \(component): \(done)") }
        return String(localized: "Downloading \(component): \(done) of \(total.formatted(.byteCount(style: .file)))")
    }

    /// Runs highball-env with `arguments`, passing status lines to `progress`. Throws with the
    /// helper's own error line when it fails.
    static func run(helper: URL, arguments: [String], progress: @escaping @Sendable (String) -> Void) async throws {
        let process = Process()
        process.executableURL = helper
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        let collector = LineCollector(progress: progress)
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil } else { collector.append(data) }
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
                process.terminationHandler = { _ in done.resume() }
                do { try process.run() } catch {
                    process.terminationHandler = nil
                    done.resume(throwing: error)
                }
            }
        } onCancel: {
            process.terminate()
        }
        output.fileHandleForReading.readabilityHandler = nil
        collector.append(output.fileHandleForReading.readDataToEndOfFile())
        collector.finish()
        try Task.checkCancellation()
        guard process.terminationStatus == 0 else {
            throw StepFailure(step: step, detail: collector.lastError
                ?? String(localized: "highball-env failed with status \(process.terminationStatus)."))
        }
    }

    final class LineCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var pending = Data()
        private let progress: @Sendable (String) -> Void
        private(set) var lastError: String?

        init(progress: @escaping @Sendable (String) -> Void) { self.progress = progress }

        func append(_ data: Data) {
            lock.lock()
            defer { lock.unlock() }
            pending.append(data)
            while let newline = pending.firstIndex(of: 0x0A) {
                let line = String(decoding: pending[pending.startIndex..<newline], as: UTF8.self)
                pending.removeSubrange(pending.startIndex...newline)
                handle(line)
            }
        }

        func finish() {
            lock.lock()
            defer { lock.unlock() }
            if !pending.isEmpty { handle(String(decoding: pending, as: UTF8.self)) }
            pending.removeAll()
        }

        private func handle(_ line: String) {
            AppLog.note("highball-env: \(line)")
            if line.hasPrefix("# error: ") { lastError = String(line.dropFirst("# error: ".count)) }
            if let label = HighballInstaller.label(forLine: line) { progress(label) }
        }
    }
}
