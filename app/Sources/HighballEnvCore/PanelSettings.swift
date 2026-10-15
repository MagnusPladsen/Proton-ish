// Steam's game options panel stores its choices as launch-option variables; this turns them into
// the Highball settings a Highball environment with the same choices would have.

import HighballKit

public enum PanelSettings {

    public static func bottleSettings(environment env: [String: String], engineID: String) -> BottleSettings {
        var settings = BottleSettings(name: "steam", engineID: engineID)
        if let renderer = env["CX_GRAPHICS_BACKEND"].flatMap(Renderer.init(rawValue:)) {
            settings.renderer = renderer
            settings.rendererExplicit = true
        }
        settings.metalHUD = env["MTL_HUD_ENABLED"] == "1"
        settings.advertiseAVX = env["ROSETTA_ADVERTISE_AVX"] == "1"
        switch env["WINEMSYNC"] {
        case "0": settings.sync = .none
        case "1": settings.sync = .msync
        default: break
        }
        settings.dlssEnabled = env["DXMT_ENABLE_NVEXT"] == "1" || env["D3DM_ENABLE_METALFX"] == "1"
        settings.dllOverrides = env["WINEDLLOVERRIDES"] ?? ""
        return settings
    }
}
