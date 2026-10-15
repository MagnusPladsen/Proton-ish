import Foundation
import HighballKit
import Testing

@testable import HighballEnvCore

@Suite("Launch environment from a Highball install")
struct LaunchEnvironmentTests {

    static let engineID = "x64-crossover26.3-r19"

    struct Install {
        let home: URL
        let prefix: URL
        var engine: URL { home.appending(path: "engines/\(LaunchEnvironmentTests.engineID)") }
    }

    private func install(renderers: [String], licensed: Bool = false, direct3D9: String = "wined3d") throws -> Install {
        let work = FileManager.default.temporaryDirectory.appending(path: "hb-env-\(UUID().uuidString)")
        let install = Install(home: work.appending(path: "Highball"), prefix: work.appending(path: "pfx"))
        let fm = FileManager.default
        try fm.createDirectory(at: install.prefix.appending(path: "drive_c"), withIntermediateDirectories: true)
        for name in renderers {
            let base = name == "dxmt" ? "renderers/\(name)" : "frameworks/renderer/\(name)"
            try fm.createDirectory(at: install.engine.appending(path: "\(base)/wine/x86_64-windows"),
                                   withIntermediateDirectories: true)
        }
        var manifest: [String: Any] = [
            "id": Self.engineID, "displayName": "Wine 11.0 (CrossOver 26.3) r19", "arch": "x86_64",
            "minMacOS": "14.0", "requires": ["rosetta2"], "direct3D9": direct3D9, "components": [String: Any](),
            "baseEnv": ["DXMT_ALLOW_CROSS_PROCESS_SWAPCHAIN": "1"],
        ]
        if licensed { manifest["acceptedLicenses"] = ["apple-gptk-license-2023-08-17"] }
        try fm.createDirectory(at: install.engine, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: manifest).write(to: install.engine.appending(path: "manifest.json"))
        return install
    }

    private func run(_ install: Install, _ env: [String: String] = [:]) -> [String] {
        LaunchEnvironment.lines(for: .init(prefix: install.prefix, engineID: Self.engineID, appID: nil,
                                           environment: env, paths: HighballPaths(home: install.home)))
    }

    private func value(_ key: String, in lines: [String]) -> String? {
        lines.first { $0.hasPrefix(key + "=") }.map { String($0.dropFirst(key.count + 1)) }
    }

    @Test("Automatic runs DXMT from the engine's renderers folder")
    func automaticIsDXMT() throws {
        let hb = try install(renderers: ["dxmt"])
        let out = run(hb)
        #expect(out.contains("# note: renderer dxmt"))
        #expect(value("WINEDLLPATH_PREPEND", in: out) == hb.engine.appending(path: "renderers/dxmt/wine").path)
        #expect(value("DXMT_ALLOW_CROSS_PROCESS_SWAPCHAIN", in: out) == "1")
    }

    @Test("D3DMetal without Apple's licence falls back to DXMT and says why")
    func d3dmetalNeedsLicence() throws {
        let hb = try install(renderers: ["dxmt", "d3dmetal"])
        let out = run(hb, ["CX_GRAPHICS_BACKEND": "d3dmetal"])
        #expect(out.contains("# note: renderer dxmt"))
        #expect(out.contains { $0.hasPrefix("# note: running with DXMT instead of D3DMetal") })
        #expect(value("CX_D3DMETALPATH", in: out) == nil)
    }

    @Test("D3DMetal with the licence accepted points Wine at the user's D3DMetal, with DXMT for 32-bit")
    func d3dmetalLicensed() throws {
        let hb = try install(renderers: ["dxmt", "d3dmetal"], licensed: true)
        let out = run(hb, ["CX_GRAPHICS_BACKEND": "d3dmetal"])
        let d3dmetal = hb.engine.appending(path: "frameworks/renderer/d3dmetal")
        #expect(value("CX_D3DMETALPATH", in: out) == d3dmetal.appending(path: "external").path)
        #expect(value("WINEDLLPATH_PREPEND", in: out)
                == d3dmetal.appending(path: "wine").path + ":" + hb.engine.appending(path: "renderers/dxmt/wine").path)
        #expect(value("DYLD_FALLBACK_FRAMEWORK_PATH", in: out)?.hasPrefix(d3dmetal.appending(path: "external").path) == true)
    }

    @Test("DXVK overrides Direct3D and keeps the user's own overrides winning")
    func dxvkKeepsUserOverrides() throws {
        let hb = try install(renderers: ["dxmt", "dxvk", "d9vk"])
        let out = run(hb, ["CX_GRAPHICS_BACKEND": "dxvk", "WINEDLLOVERRIDES": "d3d11=b"])
        let overrides = try #require(value("WINEDLLOVERRIDES", in: out))
        #expect(overrides.hasPrefix("dxgi,d3d9,d3d10core,d3d11=n,b"))
        #expect(overrides.hasSuffix(";d3d11=b"))
    }

    @Test("WineD3D adds no renderer folder")
    func wined3d() throws {
        let hb = try install(renderers: ["dxmt"])
        #expect(value("WINEDLLPATH_PREPEND", in: run(hb, ["CX_GRAPHICS_BACKEND": "wined3d"])) == nil)
    }

    @Test("A missing engine gives only an error note, so the run script falls back")
    func missingEngine() throws {
        let hb = try install(renderers: [])
        try FileManager.default.removeItem(at: hb.engine)
        let out = run(hb)
        #expect(out.count == 1)
        #expect(out.first?.hasPrefix("# error: ") == true)
    }

    @Test("Highball's DXVK config is written into the prefix for every renderer but WineD3D")
    func writesDxvkConfig() throws {
        let hb = try install(renderers: ["dxmt"])
        _ = run(hb)
        #expect(FileManager.default.fileExists(atPath: hb.prefix.appending(path: "drive_c/highball/dxvk.conf").path))
    }
}
