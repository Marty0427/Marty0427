import PhotosUI
import SwiftUI
import UIKit

/// Picks an image from the photo library and reads any barcode in it.
///
/// Uses `PhotosPicker`, which runs out of process: PocketPass never gets access to the
/// library, only to the one image chosen.
struct PhotoImportScreen: View {
    var onResult: (ScanResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selection: PhotosPickerItem?
    @State private var phase: Phase = .idle

    private enum Phase {
        case idle
        case working
        case choose([ScanResult])
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .idle:
                    idleView
                case .working:
                    ProgressView("Looking for a code…")
                case .choose(let results):
                    chooser(results)
                case .failed(let message):
                    ContentUnavailableView {
                        Label("No Code Found", systemImage: "photo.badge.exclamationmark")
                    } description: {
                        Text(message)
                    } actions: {
                        PhotosPicker("Choose Another Photo", selection: $selection, matching: .images)
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("Import from Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onChange(of: selection) { _, item in
                guard let item else { return }
                Task { await load(item) }
            }
        }
    }

    private var idleView: some View {
        ContentUnavailableView {
            Label("Pick a Photo", systemImage: "photo.on.rectangle.angled")
        } description: {
            Text("Choose a screenshot of a boarding pass, an emailed ticket or a photo of a loyalty card.")
        } actions: {
            PhotosPicker("Choose Photo", selection: $selection, matching: .images)
                .buttonStyle(.borderedProminent)
        }
    }

    private func chooser(_ results: [ScanResult]) -> some View {
        List(results, id: \.payload) { result in
            Button {
                onResult(result)
                dismiss()
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.payload)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(2)
                    Text(result.symbology.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Choose a Code")
    }

    @MainActor
    private func load(_ item: PhotosPickerItem) async {
        phase = .working
        do {
            guard
                let data = try await item.loadTransferable(type: Data.self),
                let image = UIImage(data: data)
            else {
                phase = .failed(ImageBarcodeDetector.DetectionError.noImageData.localizedDescription)
                return
            }

            let results = try await ImageBarcodeDetector.detect(in: image)
            if results.count == 1, let only = results.first {
                onResult(only)
                dismiss()
            } else {
                phase = .choose(results)
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}

#Preview {
    PhotoImportScreen { _ in }
}
