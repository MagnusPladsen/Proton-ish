import AppKit
import Foundation

// x86_64 Wine (every Highball engine, CrossOver under Rosetta) runs on Apple silicon through
// Rosetta 2, which macOS does not install until something asks for it. Without it a game fails
// with "OS Error 0"; the run script stops the launch and says so, this warns ahead of it.
enum Rosetta {
    static let installCommand = "softwareupdate --install-rosetta --agree-to-license"

    // The runtime itself: oah can exist without it, holding only RosettaLinux
    static let runtime = URL(filePath: "/Library/Apple/usr/libexec/oah/libRosettaRuntime")

    static var isAppleSilicon: Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0 && value == 1
    }

    static func isMissing(appleSilicon: Bool = isAppleSilicon, runtime: URL = runtime) -> Bool {
        appleSilicon && !FileManager.default.fileExists(atPath: runtime.path(percentEncoded: false))
    }

    static func copyInstallCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(installCommand, forType: .string)
    }
}
