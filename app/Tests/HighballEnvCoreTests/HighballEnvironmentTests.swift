import Testing

@testable import HighballEnvCore

@Suite("Highball environment output")
struct HighballEnvironmentTests {

    private func lines(_ highball: [String: String], user: [String: String] = [:], notes: [String] = []) -> [String] {
        HighballEnvironment.lines(highball: highball, user: user, notes: notes)
    }

    @Test("Variables that point at Proton-ish's engine and prefix are left to the run script")
    func dropsOwnedKeys() {
        let out = lines(["WINEPREFIX": "/hb", "WINELOADER": "/hb/wine", "WINESERVER": "/hb/server", "PATH": "/hb/bin",
                         "WINEDLLPATH": "/hb/lib", "WINEUSERNAME": "x", "CX_ROOT": "/hb", "GST_PLUGIN_PATH": "/hb/gst"])
        #expect(out == ["GST_PLUGIN_PATH=/hb/gst"])
    }

    @Test("A renderer variable the user typed wins over Highball's")
    func userWins() {
        let out = lines(["DXVK_HUD": "0", "MTL_HUD_ENABLED": "1", "WINEDEBUG": "fixme-all", "D3DM_MAX_FPS": "60"],
                        user: ["DXVK_HUD": "fps", "WINEDEBUG": "+loaddll"])
        #expect(out == ["D3DM_MAX_FPS=60", "MTL_HUD_ENABLED=1"])
    }

    @Test("DXMT settings from Highball and the user are joined, the user's last")
    func joinsDXMTConfig() {
        let out = lines(["DXMT_CONFIG": "d3d11.preferredMaxFrameRate=60;"],
                        user: ["DXMT_CONFIG": "d3d11.metalSpatialUpscaleFactor=2"])
        #expect(out == ["DXMT_CONFIG=d3d11.preferredMaxFrameRate=60;d3d11.metalSpatialUpscaleFactor=2"])
    }

    @Test("A value with a line break is never printed")
    func rejectsLineBreaks() {
        let out = lines(["GOOD": "1", "BAD": "a\nWINELOADER=/evil"])
        #expect(out == ["# skipped: BAD has a line break", "GOOD=1"])
    }

    @Test("A name the run script would refuse is never printed")
    func rejectsInvalidNames() {
        let out = lines(["lower": "1", "1ST": "1", "A-B": "1", "OK_1": "1"])
        #expect(out.filter { !$0.hasPrefix("#") } == ["OK_1=1"])
    }

    @Test("Notes become one-line comments before the variables")
    func notesAsComments() {
        let out = lines(["A": "1"], notes: ["running with DXMT\ninstead"])
        #expect(out == ["# note: running with DXMT instead", "A=1"])
    }
}
