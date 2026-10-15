import HighballKit
import Testing

@testable import HighballEnvCore

@Suite("Panel settings")
struct PanelSettingsTests {

    private func settings(_ env: [String: String]) -> BottleSettings {
        PanelSettings.bottleSettings(environment: env, engineID: "x64-crossover26.3-r19")
    }

    @Test("Automatic leaves the renderer to Highball and the game database")
    func automatic() {
        let picked = settings([:])
        #expect(picked.renderer == .dxmt)
        #expect(!picked.rendererExplicit)
    }

    @Test("Each Graphics dropdown entry picks its renderer explicitly",
          arguments: [("dxmt", Renderer.dxmt), ("d3dmetal", .d3dmetal), ("dxvk", .dxvk), ("wined3d", .wined3d)])
    func explicitRenderer(value: String, renderer: Renderer) {
        let picked = settings(["CX_GRAPHICS_BACKEND": value])
        #expect(picked.renderer == renderer)
        #expect(picked.rendererExplicit)
    }

    @Test("An unknown Graphics value counts as Automatic")
    func unknownRenderer() {
        let picked = settings(["CX_GRAPHICS_BACKEND": "glide"])
        #expect(picked.renderer == .dxmt)
        #expect(!picked.rendererExplicit)
    }

    @Test("Metal HUD, AVX2 and DLSS switches carry over")
    func switches() {
        let picked = settings(["MTL_HUD_ENABLED": "1", "ROSETTA_ADVERTISE_AVX": "1", "DXMT_ENABLE_NVEXT": "1"])
        #expect(picked.metalHUD)
        #expect(picked.advertiseAVX)
        #expect(picked.dlssEnabled)
    }

    @Test("D3DMetal's DLSS switch also enables DLSS")
    func d3dmetalDLSS() {
        #expect(settings(["D3DM_ENABLE_METALFX": "1"]).dlssEnabled)
    }

    @Test("Switches that are off or absent stay off")
    func switchesOff() {
        let picked = settings(["MTL_HUD_ENABLED": "", "ROSETTA_ADVERTISE_AVX": "0"])
        #expect(!picked.metalHUD)
        #expect(!picked.advertiseAVX)
        #expect(!picked.dlssEnabled)
    }

    @Test("MSync off turns sync off, absent keeps Highball's default",
          arguments: [("0", SyncMode.none), ("1", .msync)])
    func msync(value: String, mode: SyncMode) {
        #expect(settings(["WINEMSYNC": value]).sync == mode)
    }

    @Test("Without an MSync choice the sync mode is Highball's default")
    func msyncDefault() {
        #expect(settings([:]).sync == BottleSettings(name: "default", engineID: "x").sync)
    }

    @Test("The user's DLL overrides become the bottle's, so Highball keeps them winning")
    func dllOverrides() {
        #expect(settings(["WINEDLLOVERRIDES": "d3d11=b;dinput8=n,b"]).dllOverrides == "d3d11=b;dinput8=n,b")
    }
}
