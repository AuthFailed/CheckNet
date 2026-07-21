import SwiftUI
#if os(iOS)
import AVFoundation
import VisionKit

/// Live QR scanning built on the system data scanner, so the camera UI and its
/// affordances match the rest of iOS.
struct QRScannerSheet: View {
    /// Called with the raw payload of the first QR code recognised.
    let onFound: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var access: CameraAccess = .undetermined

    enum CameraAccess { case undetermined, granted, denied, unsupported }

    var body: some View {
        NavigationStack {
            Group {
                switch access {
                case .granted:
                    scanner
                case .undetermined:
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .denied:
                    ContentUnavailableView {
                        Label("Нет доступа к камере", systemImage: "camera.fill")
                    } description: {
                        Text("Разрешите доступ к камере в Настройках iOS, чтобы сканировать QR-коды.")
                    } actions: {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            Link("Открыть Настройки", destination: url)
                        }
                    }
                case .unsupported:
                    ContentUnavailableView {
                        Label("Сканирование недоступно", systemImage: "qrcode.viewfinder")
                    } description: {
                        Text("Это устройство не поддерживает сканирование камерой. Вставьте ссылку из буфера обмена.")
                    }
                }
            }
            .navigationTitle("Сканировать QR")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
            .task { await resolveAccess() }
        }
    }

    private var scanner: some View {
        ZStack(alignment: .bottom) {
            DataScannerRepresentable { payload in
                onFound(payload)
                dismiss()
            }
            .ignoresSafeArea(edges: .bottom)

            Text("Наведите камеру на QR-код из CheckNet")
                .font(.footnote)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.bottom, 28)
        }
    }

    private func resolveAccess() async {
        guard DataScannerViewController.isSupported, DataScannerViewController.isAvailable else {
            access = .unsupported
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            access = .granted
        case .notDetermined:
            access = await AVCaptureDevice.requestAccess(for: .video) ? .granted : .denied
        default:
            access = .denied
        }
    }
}

/// Hosts `DataScannerViewController` and reports the first QR payload it sees.
private struct DataScannerRepresentable: UIViewControllerRepresentable {
    let onFound: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFound: onFound) }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        try? controller.startScanning()
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onFound: (String) -> Void
        /// The scanner keeps firing for the same code; only the first one counts.
        private var handled = false

        init(onFound: @escaping (String) -> Void) { self.onFound = onFound }

        func dataScanner(_ scanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            deliver(from: addedItems, scanner: scanner)
        }

        func dataScanner(_ scanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            deliver(from: [item], scanner: scanner)
        }

        private func deliver(from items: [RecognizedItem], scanner: DataScannerViewController) {
            guard !handled else { return }
            for case let .barcode(barcode) in items {
                guard let payload = barcode.payloadStringValue else { continue }
                handled = true
                scanner.stopScanning()
                onFound(payload)
                return
            }
        }
    }
}
#endif
