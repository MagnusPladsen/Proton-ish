import Foundation
import HighballKit
import Testing

@testable import HighballEnvCore

@Suite("Direct3D 12-only games on Automatic")
struct Direct3D12TakeOverTests {

    static let engineID = "x64-crossover26.3-r19"

    // A minimal 64-bit PE whose import table names `imports`, after Highball's own test builder
    // (Tests/HighballKitTests/PEImportsTests.swift, GPL-3.0)
    static func makePE(imports: [String]) -> Data {
        let imageBase = 0x400000, sectionVA = 0x1000, sectionRaw = 0x200
        var section = Data()
        func put32(_ v: UInt32) { for i in 0..<4 { section.append(UInt8((v >> (8 * i)) & 0xFF)) } }
        var nameRVA: [String: UInt32] = [:]
        for n in imports where nameRVA[n] == nil {
            nameRVA[n] = UInt32(sectionVA + section.count)
            section.append(contentsOf: Array(n.utf8) + [0])
        }
        while section.count % 4 != 0 { section.append(0) }
        let importOff = section.count
        for n in imports { put32(0); put32(0); put32(0); put32(nameRVA[n]!); put32(UInt32(sectionVA)) }
        put32(0); put32(0); put32(0); put32(0); put32(0)
        for _ in 0..<8 { put32(0) }
        var d = Data(count: sectionRaw)
        func w16(_ v: UInt16, _ o: Int) { d[o] = UInt8(v & 0xFF); d[o + 1] = UInt8(v >> 8) }
        func w32(_ v: UInt32, _ o: Int) { for i in 0..<4 { d[o + i] = UInt8((v >> (8 * i)) & 0xFF) } }
        d[0] = 0x4D; d[1] = 0x5A; w32(0x40, 0x3C)
        let pe = 0x40
        w32(0x4550, pe); w16(0x8664, pe + 4); w16(1, pe + 6); w16(240, pe + 20)
        let opt = pe + 24
        w16(0x20B, opt)
        w32(UInt32(imageBase & 0xFFFFFFFF), opt + 24); w32(UInt32(imageBase >> 32), opt + 28)
        w32(16, opt + 108)
        let dd = opt + 112
        w32(UInt32(sectionVA + importOff), dd + 8); w32(UInt32(section.count - importOff), dd + 12)
        let table = opt + 240
        d.replaceSubrange(table..<table + 8, with: Array(".idata\0\0".utf8))
        w32(UInt32(section.count), table + 8); w32(UInt32(sectionVA), table + 12)
        w32(UInt32(section.count), table + 16); w32(UInt32(sectionRaw), table + 20)
        d.append(section)
        return d
    }

    struct Install {
        let home: URL
        let prefix: URL
        let exe: URL
    }

    private func install(imports: [String], licensed: Bool) throws -> Install {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appending(path: "hb-dx12-\(UUID().uuidString)")
        let engine = work.appending(path: "Highball/engines/\(Self.engineID)")
        for base in ["renderers/dxmt", "frameworks/renderer/d3dmetal"] {
            try fm.createDirectory(at: engine.appending(path: "\(base)/wine/x86_64-windows"), withIntermediateDirectories: true)
        }
        var manifest: [String: Any] = ["id": Self.engineID, "displayName": "r19", "arch": "x86_64", "minMacOS": "14.0",
                                       "direct3D9": "wined3d", "components": [String: Any]()]
        if licensed { manifest["acceptedLicenses"] = ["apple-gptk-license-2023-08-17"] }
        try JSONSerialization.data(withJSONObject: manifest).write(to: engine.appending(path: "manifest.json"))
        let game = work.appending(path: "game")
        try fm.createDirectory(at: game, withIntermediateDirectories: true)
        let exe = game.appending(path: "Game.exe")
        try Self.makePE(imports: imports).write(to: exe)
        try fm.createDirectory(at: work.appending(path: "pfx/drive_c"), withIntermediateDirectories: true)
        return Install(home: work.appending(path: "Highball"), prefix: work.appending(path: "pfx"), exe: exe)
    }

    private func renderer(_ hb: Install, env: [String: String] = [:], exe: Bool = true) -> String? {
        let lines = LaunchEnvironment.lines(for: .init(
            prefix: hb.prefix, engineID: Self.engineID, appID: nil, environment: env,
            exe: exe ? hb.exe : nil, paths: HighballPaths(home: hb.home)))
        return lines.first { $0.hasPrefix("# note: renderer ") }.map { String($0.dropFirst("# note: renderer ".count)) }
    }

    @Test("A game that imports only Direct3D 12 gets D3DMetal on Automatic")
    func dx12OnlyGoesToD3DMetal() throws {
        let hb = try install(imports: ["KERNEL32.dll", "d3d12.dll"], licensed: true)
        #expect(renderer(hb) == "d3dmetal")
    }

    @Test("A game with Direct3D 11 too stays on Highball's default")
    func dx11StaysDXMT() throws {
        let hb = try install(imports: ["d3d12.dll", "d3d11.dll"], licensed: true)
        #expect(renderer(hb) == "dxmt")
    }

    @Test("A Graphics choice the user made stands")
    func userChoiceStands() throws {
        let hb = try install(imports: ["d3d12.dll"], licensed: true)
        #expect(renderer(hb, env: ["CX_GRAPHICS_BACKEND": "dxmt"]) == "dxmt")
    }

    @Test("Without the executable nothing changes")
    func noExe() throws {
        let hb = try install(imports: ["d3d12.dll"], licensed: true)
        #expect(renderer(hb, exe: false) == "dxmt")
    }

    @Test("Without Apple's licence the game stays on DXMT and the log says how to enable D3DMetal")
    func unlicensedStaysWithNote() throws {
        let hb = try install(imports: ["d3d12.dll"], licensed: false)
        let lines = LaunchEnvironment.lines(for: .init(
            prefix: hb.prefix, engineID: Self.engineID, appID: nil, environment: [:],
            exe: hb.exe, paths: HighballPaths(home: hb.home)))
        #expect(lines.contains("# note: renderer dxmt"))
        #expect(lines.contains { $0.hasPrefix("# note: Game.exe only has Direct3D 12, but") && $0.contains("Enable D3DMetal") })
    }
}
