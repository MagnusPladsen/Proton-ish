// Why buying CrossOver supports Wine: shown once on first launch and from Help → Support Wine Development

import SwiftUI

struct FundingNoticeSheet: View {

    let acknowledge: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Support Wine development").font(.headline)
            Text("Proton-ish is free, and so is Highball's engine. Both run on Wine, and most Wine development is done by CodeWeavers, the company behind CrossOver.")
            Text("Buying CrossOver is the most direct way to support future Wine development. Proton-ish fully supports it alongside Highball's engine, so you can use either.")
            Text("Either way, enjoy your games. This note is always under Help → Support Wine Development.")
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
