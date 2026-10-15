// Apple's D3DMetal licence, shown before Proton-ish downloads Highball's engine or turns D3DMetal on

import SwiftUI

struct HighballLicenceSheet: View {

    enum Mode: Identifiable {
        case download(bytes: Int64)
        case enable(HighballEngine)

        var id: String {
            switch self {
            case .download: "download"
            case .enable(let engine): "enable-\(engine.id)"
            }
        }
    }

    enum Choice { case accept, decline }

    let mode: Mode
    let licence: String
    let choose: (Choice) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            Text(intro).fixedSize(horizontal: false, vertical: true)
            Text("Apple's licence for D3DMetal").font(.subheadline.weight(.semibold))
            ScrollView {
                Text(licence)
                    .font(.caption)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(minHeight: 240)
            .background(.background.secondary, in: .rect(cornerRadius: 6))
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if case .download = mode {
                    Button("Download without D3DMetal") { finish(.decline) }
                }
                Button(acceptLabel) { finish(.accept) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 580)
    }

    private var title: String {
        switch mode {
        case .download: String(localized: "Download the Highball engine")
        case .enable: String(localized: "Enable D3DMetal")
        }
    }

    private var intro: String {
        switch mode {
        case .download(let bytes):
            String(localized: "Proton-ish downloads Highball's free Wine engine (\(bytes.formatted(.byteCount(style: .file)))) from Highball's releases on GitHub, with Highball's own installer, into Highball's folder. D3DMetal, Apple's DirectX 12 translator, comes with it and is used only if you accept Apple's licence below. Without it, games use DXMT or DXVK and DirectX 12-only games will not start.")
        case .enable(let engine):
            String(localized: "D3DMetal is already part of \(engine.displayName). Accepting Apple's licence below lets games use it.")
        }
    }

    private var acceptLabel: String {
        switch mode {
        case .download: String(localized: "Accept and Download")
        case .enable: String(localized: "Accept")
        }
    }

    private func finish(_ choice: Choice) {
        dismiss()
        choose(choice)
    }
}
