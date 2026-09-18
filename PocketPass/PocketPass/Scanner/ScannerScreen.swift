import AVFoundation
import SwiftUI
import UIKit

/// Full screen camera scanner with permission handling and a torch toggle.
struct ScannerScreen: View {
    /// Delivered once, for the first code that could be stored.
    var onResult: (ScanResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettings

    @State private var authorization = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var isTorchOn = false
    @State private var resumeCounter = 0
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                switch authorization {
                case .authorized:
                    cameraLayer
                case .notDetermined:
                    ProgressView()
                        .tint(.white)
                        .task { await requestAccess() }
                default:
                    permissionDeniedView
                }
            }
            .navigationTitle("Scan Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if authorization == .authorized {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            isTorchOn.toggle()
                        } label: {
                            Label(
                                isTorchOn ? "Turn off torch" : "Turn on torch",
                                systemImage: isTorchOn ? "bolt.fill" : "bolt.slash"
                            )
                        }
                    }
                }
            }
        }
    }

    private var cameraLayer: some View {
        ZStack {
            BarcodeCaptureView(
                isTorchOn: isTorchOn,
                resumeToken: resumeCounter,
                onCapture: handleCapture,
                onFailure: { problem = $0 }
            )
            .ignoresSafeArea()

            VStack {
                Spacer()
                if let problem {
                    problemBanner(problem)
                } else {
                    Text("Line the card’s code up inside the frame")
                        .font(.footnote)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.black.opacity(0.55), in: Capsule())
                }
            }
            .padding(.bottom, 44)
            .animation(.default, value: problem)
        }
    }

    private func problemBanner(_ message: String) -> some View {
        VStack(spacing: 12) {
            Text(message)
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
            Button("Try Again") {
                problem = nil
                resumeCounter += 1
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(20)
        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 24)
    }

    private var permissionDeniedView: some View {
        ContentUnavailableView {
            Label("Camera Access Needed", systemImage: "camera.metering.unknown")
        } description: {
            Text("PocketPass uses the camera only to read a card’s barcode. Nothing is recorded or uploaded.")
        } actions: {
            Button("Open Settings") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
            .buttonStyle(.borderedProminent)
        }
        .foregroundStyle(.white)
    }

    @MainActor
    private func requestAccess() async {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        authorization = granted ? .authorized : .denied
    }

    private func handleCapture(payload: String, objectType: AVMetadataObject.ObjectType) {
        switch ScanResultMapper.outcome(payload: payload, objectType: objectType) {
        case .recognized(let result):
            Haptics.success(enabled: settings.hapticsEnabled)
            onResult(result)
            dismiss()
        case .unsupportedFormat(let name):
            Haptics.warning(enabled: settings.hapticsEnabled)
            problem = "\(name) codes can’t be stored yet, because PocketPass can’t draw them back."
        case .unreadable(let message):
            Haptics.warning(enabled: settings.hapticsEnabled)
            problem = message
        }
    }
}

/// Hosts `BarcodeCaptureController` in SwiftUI.
private struct BarcodeCaptureView: UIViewControllerRepresentable {
    var isTorchOn: Bool
    /// Bumping this value tells the controller to start delivering codes again.
    var resumeToken: Int
    var onCapture: (String, AVMetadataObject.ObjectType) -> Void
    var onFailure: (String) -> Void

    func makeUIViewController(context: Context) -> BarcodeCaptureController {
        let controller = BarcodeCaptureController()
        controller.onCapture = onCapture
        controller.onSetupFailure = onFailure
        context.coordinator.lastResumeToken = resumeToken
        return controller
    }

    func updateUIViewController(_ controller: BarcodeCaptureController, context: Context) {
        controller.onCapture = onCapture
        controller.onSetupFailure = onFailure
        controller.setTorch(on: isTorchOn)

        if context.coordinator.lastResumeToken != resumeToken {
            context.coordinator.lastResumeToken = resumeToken
            controller.resume()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var lastResumeToken = 0
    }
}
