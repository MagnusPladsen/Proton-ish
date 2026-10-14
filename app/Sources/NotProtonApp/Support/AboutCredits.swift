// Fork credit shown in the About panel

import AppKit

enum AboutCredits {

    static var text: String {
        String(localized: """
        Proton-ish is a fork of NotProton by NotProtonNot (https://github.com/NotProtonNot/NotProton), \
        released under GPLv3. It is not affiliated with or endorsed by NotProton, Valve, CodeWeavers or Highball.
        """)
    }

    @MainActor
    static func show() {
        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(string: text)
        ])
        NSApplication.shared.activate()
    }
}
