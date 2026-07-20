import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

/// Generates QR codes for share links. Generation needs no permissions — only a
/// scanner would (camera).
enum QRCode {
    /// Renders `string` as a crisp, nearest-neighbour scaled QR bitmap.
    static func cgImage(for string: String, scale: CGFloat = 12) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return CIContext().createCGImage(scaled, from: scaled.extent)
    }

    static func image(for string: String, scale: CGFloat = 12) -> Image? {
        cgImage(for: string, scale: scale).map { Image(decorative: $0, scale: 1) }
    }
}

/// A QR code on the white plate scanners expect, regardless of app theme.
struct QRCodeView: View {
    let text: String

    var body: some View {
        Group {
            if let image = QRCode.image(for: text) {
                image
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel("QR-код со ссылкой на список хостов")
            } else {
                ContentUnavailableView("Не удалось построить QR-код", systemImage: "qrcode")
            }
        }
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
