import SwiftUI

// MARK: - Card

/// A rounded grouped-cell card matching iOS system styling.
struct CardModifier: ViewModifier {
    var cornerRadius: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .background(Palette.card, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Palette.hairline, lineWidth: 0.5)
            )
    }
}

extension View {
    func card(cornerRadius: CGFloat = 16) -> some View {
        modifier(CardModifier(cornerRadius: cornerRadius))
    }
}

enum Palette {
    static var card: Color {
        #if os(iOS)
        Color(.secondarySystemGroupedBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }
    static var groupedBackground: Color {
        #if os(iOS)
        Color(.systemGroupedBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }
    static let hairline = Color.primary.opacity(0.06)
}

// MARK: - Pulse animation

/// A subtle opacity pulse for "live" indicators.
struct PulseModifier: ViewModifier {
    @State private var on = false
    func body(content: Content) -> some View {
        content
            .opacity(on ? 1 : 0.35)
            .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}

/// A pulsing ring around the current latency value.
struct PulseRing: View {
    let value: Double?
    @State private var animate = false
    /// Scales with the user's text size, so the ring grows with the number it
    /// encircles instead of clipping it.
    @ScaledMetric(relativeTo: .title2) private var diameter: CGFloat = 64

    var body: some View {
        ZStack {
            ForEach(0..<2, id: \.self) { i in
                Circle()
                    .strokeBorder(Color.blue, lineWidth: 2)
                    .scaleEffect(animate ? 1.2 : 0.66)
                    .opacity(animate ? 0 : 0.6)
                    .animation(.easeOut(duration: 1.6).repeatForever(autoreverses: false).delay(Double(i) * 0.8),
                               value: animate)
            }
            Text(value.map { String(format: $0 >= 100 ? "%.0f" : "%.0f", $0) } ?? "—")
                .font(.title2.weight(.bold).monospaced())
                .foregroundStyle(.blue)
                .contentTransition(.numericText())
        }
        .frame(width: diameter, height: diameter)
        .onAppear { animate = true }
    }
}

// MARK: - Sparkline

/// A lightweight latency sparkline drawn with a Path.
struct Sparkline: View {
    let values: [Double]

    var body: some View {
        GeometryReader { geo in
            let pts = points(in: geo.size)
            if pts.count > 1 {
                Path { p in
                    p.move(to: pts[0])
                    for pt in pts.dropFirst() { p.addLine(to: pt) }
                }
                .stroke(Color.blue, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            } else {
                Path { p in
                    p.move(to: CGPoint(x: 0, y: geo.size.height / 2))
                    p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height / 2))
                }
                .stroke(Palette.hairline, lineWidth: 1)
            }
        }
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let minV = values.min() ?? 0
        let maxV = values.max() ?? 1
        let range = max(maxV - minV, 0.001)
        let stepX = size.width / CGFloat(values.count - 1)
        return values.enumerated().map { idx, v in
            let x = CGFloat(idx) * stepX
            let norm = (v - minV) / range
            let y = size.height - CGFloat(norm) * size.height
            return CGPoint(x: x, y: y)
        }
    }
}
