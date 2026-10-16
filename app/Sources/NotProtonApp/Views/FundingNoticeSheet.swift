// Who pays for Wine on the Mac: shown once on first launch and from Help → Why Buy CrossOver

import SwiftUI

struct FundingNoticeSheet: View {

    let acknowledge: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Who pays for Wine on the Mac").font(.headline)
            Text("Proton-ish is free, and so is Highball's engine. The Wine underneath them is not free to make.")
            Text("CodeWeavers employs most of the people who work on Wine and funds nearly all of the Wine work for macOS. Highball's engine is built from the CrossOver sources CodeWeavers publishes. Sales of CrossOver pay for all of it.")
            Text("If you can, buy CrossOver and use it in Proton-ish: it gives the best support and performance, and it keeps Wine on the Mac alive. If you cannot, play on, and come back to this when you can. This note is always under Help → Why Buy CrossOver.")
            HStack {
                Button("Buy CrossOver") {
                    openURL(ProjectLinks.crossOver)
                    finish()
                }
                Spacer()
                Button("Continue") { finish() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 8)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(20)
        .frame(width: 520)
    }

    private func finish() {
        acknowledge()
        dismiss()
    }
}
