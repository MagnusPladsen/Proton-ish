// What a Highball engine's Status row says about Steam: whether Windows games without their
// own choice run through it, or which engine to pick when they do not

import Foundation

enum EngineGuidance {
    enum Role: Equatable, Sendable {
        case steamDefault     // Steam's config names this engine's tool
        case pendingDefault   // requested; Steam applies it when it starts again
        case newest           // the newest supported engine, not the default
        case plain
    }

    // `request` is the app's default-tool request (nil: none, "": clear);
    // `steamDefault` is what Steam's config names right now
    static func role(build: RunnerBuild, newest: RunnerBuild?, request: String?, steamDefault: String?) -> Role {
        let tool = build.tools.first?.name
        let otherRequested = request.map { $0 != tool } ?? false
        if !otherRequested, let tool, steamDefault == tool { return .steamDefault }
        if let tool, request == tool { return .pendingDefault }
        if build.id == newest?.id { return .newest }
        return .plain
    }
}
