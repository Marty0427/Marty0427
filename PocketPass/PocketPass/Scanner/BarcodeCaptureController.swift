import AVFoundation
import UIKit

/// Live camera preview that reports the first barcode it recognises.
///
/// Session setup and teardown happen off the main thread — `AVCaptureSession.startRunning()`
/// blocks, and doing it on the main queue is a visible hitch when the scanner opens.
final class BarcodeCaptureController: UIViewController {

    /// Called on the main queue for each accepted code. Delivery pauses until `resume()`.
    var onCapture: ((String, AVMetadataObject.ObjectType) -> Void)?
    /// Called when the session could not be built at all (no camera, or hardware in use).
    var onSetupFailure: ((String) -> Void)?

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "app.pocketpass.capture-session")
    private let metadataOutput = AVCaptureMetadataOutput()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var isDeliveringResults = true
    private var isConfigured = false

    /// The area the preview highlights, and the only part of the frame that is searched.
    private lazy var scanWindow: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.borderColor = UIColor.white.withAlphaComponent(0.9).cgColor
        view.layer.borderWidth = 2
        view.layer.cornerRadius = 16
        view.layer.cornerCurve = .continuous
        view.backgroundColor = .clear
        return view
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        addScanWindow()
        sessionQueue.async { [weak self] in self?.configureSession() }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        isDeliveringResults = true
        sessionQueue.async { [weak self] in
            guard let self, self.isConfigured, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
        setTorch(on: false)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
        updateRegionOfInterest()
    }

    /// Re-enables delivery after the caller has dealt with a code.
    func resume() {
        isDeliveringResults = true
    }

    func setTorch(on: Bool) {
        sessionQueue.async {
            guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
            do {
                try device.lockForConfiguration()
                device.torchMode = on ? .on : .off
                device.unlockForConfiguration()
            } catch {
                // A torch that refuses to turn on is not worth interrupting a scan for.
            }
        }
    }

    // MARK: - Setup

    private func addScanWindow() {
        view.addSubview(scanWindow)
        NSLayoutConstraint.activate([
            scanWindow.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            scanWindow.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            scanWindow.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.82),
            scanWindow.heightAnchor.constraint(equalTo: scanWindow.widthAnchor, multiplier: 0.72),
        ])
    }

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .high

        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(for: .video),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            session.commitConfiguration()
            DispatchQueue.main.async { [weak self] in
                self?.onSetupFailure?("This device’s camera isn’t available.")
            }
            return
        }
        session.addInput(input)

        guard session.canAddOutput(metadataOutput) else {
            session.commitConfiguration()
            DispatchQueue.main.async { [weak self] in
                self?.onSetupFailure?("The camera couldn’t be set up for scanning.")
            }
            return
        }
        session.addOutput(metadataOutput)

        // Must be set after the output joins the session, otherwise the types are rejected.
        metadataOutput.metadataObjectTypes = ScanResultMapper.metadataObjectTypes
            .filter { metadataOutput.availableMetadataObjectTypes.contains($0) }
        metadataOutput.setMetadataObjectsDelegate(self, queue: .main)

        // Continuous autofocus, biased close up: most cards are scanned at 10-20 cm.
        if device.isFocusModeSupported(.continuousAutoFocus), (try? device.lockForConfiguration()) != nil {
            device.focusMode = .continuousAutoFocus
            if device.isAutoFocusRangeRestrictionSupported {
                device.autoFocusRangeRestriction = .near
            }
            device.unlockForConfiguration()
        }

        session.commitConfiguration()
        isConfigured = true

        DispatchQueue.main.async { [weak self] in
            self?.attachPreviewLayer()
        }

        if !session.isRunning { session.startRunning() }
    }

    private func attachPreviewLayer() {
        guard previewLayer == nil else { return }
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.insertSublayer(layer, at: 0)
        previewLayer = layer
        updateRegionOfInterest()
    }

    /// Restricts detection to the highlighted window, which speeds detection up and stops
    /// the scanner grabbing a code from the next card on the table.
    private func updateRegionOfInterest() {
        guard let previewLayer else { return }
        let rect = previewLayer.metadataOutputRectConverted(fromLayerRect: scanWindow.frame)
        guard rect.width > 0, rect.height > 0 else { return }
        sessionQueue.async { [weak self] in
            self?.metadataOutput.rectOfInterest = rect
        }
    }
}

extension BarcodeCaptureController: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard isDeliveringResults else { return }
        guard
            let object = metadataObjects.compactMap({ $0 as? AVMetadataMachineReadableCodeObject }).first,
            let payload = object.stringValue,
            !payload.isEmpty
        else {
            return
        }

        // One code at a time: the caller decides when scanning continues.
        isDeliveringResults = false
        onCapture?(payload, object.type)
    }
}
