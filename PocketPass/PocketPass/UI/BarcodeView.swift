import SwiftUI

/// Renders a payload as a scannable symbol, sized to the space it is given.
///
/// The symbol always sits on white with a margin, in light and dark mode alike: readers
/// need the quiet zone and the contrast, and inverting a barcode makes it unscannable.
struct BarcodeView: View {
    let payload: String
    let symbology: BarcodeSymbology
    var showsHumanReadable: Bool = true
    var padding: CGFloat = 12

    @Environment(\.displayScale) private var displayScale
    @State private var rendered: RenderedBarcode?
    @State private var failureMessage: String?

    var body: some View {
        VStack(spacing: 8) {
            symbolArea
            if showsHumanReadable, let text = rendered?.humanReadable, !text.isEmpty {
                Text(displayText(for: text))
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.black)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .accessibilityHidden(true)
            }
        }
        .padding(padding)
        .frame(maxWidth: .infinity)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private var symbolArea: some View {
        GeometryReader { proxy in
            ZStack {
                if let rendered {
                    Image(decorative: rendered.image, scale: 1, orientation: .up)
                        .interpolation(.none)
                        .antialiased(false)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let failureMessage {
                    failureView(failureMessage)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .task(id: renderKey(width: proxy.size.width)) {
                await render(pointWidth: proxy.size.width)
            }
        }
        .aspectRatio(symbology.preferredAspectRatio, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel(Text("\(symbology.displayName) for \(payload)"))
    }

    private func failureView(_ message: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
            Text(message)
                .font(.caption)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.black.opacity(0.7))
        .padding(8)
    }

    private func displayText(for text: String) -> String {
        guard symbology.isNumericOnly else { return text }
        return text.grouped(every: 4, separator: " ")
    }

    private func renderKey(width: CGFloat) -> String {
        "\(symbology.rawValue)|\(Int(width * displayScale))|\(payload)"
    }

    @MainActor
    private func render(pointWidth: CGFloat) async {
        guard pointWidth > 0 else { return }
        let pixelWidth = Int((pointWidth * displayScale).rounded())
        let payload = payload
        let symbology = symbology

        let result = await Task.detached(priority: .userInitiated) { () -> Result<RenderedBarcode, Error> in
            do {
                return .success(try BarcodeImageCache.shared.render(
                    payload: payload,
                    symbology: symbology,
                    pixelWidth: pixelWidth
                ))
            } catch {
                return .failure(error)
            }
        }.value

        guard !Task.isCancelled else { return }
        switch result {
        case .success(let barcode):
            rendered = barcode
            failureMessage = nil
        case .failure(let error):
            rendered = nil
            failureMessage = (error as? BarcodeError)?.errorDescription ?? error.localizedDescription
        }
    }
}

#Preview("QR") {
    BarcodeView(payload: "https://example.com/loyalty/4711", symbology: .qr)
        .padding()
}

#Preview("EAN-13") {
    BarcodeView(payload: "5901234123457", symbology: .ean13)
        .padding()
}
