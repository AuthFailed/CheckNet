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
                    .strokeBorder(Palette.hairline, lineWidth: Palette.hairlineWidth)
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
    /// Border for cards and input fields. It has to read as an edge: on macOS
    /// the card background is the same colour as the window behind it, so a
    /// 6 % hairline was invisible and fields looked like floating text.
    static var hairline: Color {
        #if os(macOS)
        Color.primary.opacity(0.22)
        #else
        Color.primary.opacity(0.12)
        #endif
    }

    /// Hairlines are 0.5 pt on Retina iOS; on macOS that renders too faint.
    static var hairlineWidth: CGFloat {
        #if os(macOS)
        1
        #else
        0.5
        #endif
    }
}

// MARK: - Pulse animation

/// A subtle opacity pulse for "live" indicators.
struct PulseModifier: ViewModifier {
    @State private var on = false
    /// An animation that never ends is the first thing "Reduce Motion" is meant
    /// to stop. The indicator stays visible — it just holds still.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(reduceMotion || on ? 1 : 0.35)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.7).repeatForever(autoreverses: true),
                       value: on)
            .onAppear { if !reduceMotion { on = true } }
    }
}

/// A pulsing ring around the current latency value.
struct PulseRing: View {
    let value: Double?
    @State private var animate = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Scales with the user's text size, so the ring grows with the number it
    /// encircles instead of clipping it.
    @ScaledMetric(relativeTo: .title2) private var diameter: CGFloat = 64

    var body: some View {
        ZStack {
            // Expanding rings are decoration around the number; with Reduce
            // Motion they become a still outline rather than nothing, so the
            // shape of the control does not change.
            ForEach(0..<2, id: \.self) { i in
                Circle()
                    .strokeBorder(Color.blue, lineWidth: 2)
                    .scaleEffect(reduceMotion ? 1 : (animate ? 1.2 : 0.66))
                    .opacity(reduceMotion ? 0.25 : (animate ? 0 : 0.6))
                    .animation(reduceMotion ? nil
                               : .easeOut(duration: 1.6).repeatForever(autoreverses: false).delay(Double(i) * 0.8),
                               value: animate)
            }
            Text(value.map { String(format: $0 >= 100 ? "%.0f" : "%.0f", $0) } ?? "—")
                .font(.title2.weight(.bold).monospaced())
                .foregroundStyle(.blue)
                .contentTransition(.numericText(value: value ?? 0))
        }
        .frame(width: diameter, height: diameter)
        .onAppear { if !reduceMotion { animate = true } }
        // Read as one value, not as a stack of rings with a number in it.
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Текущая задержка")
        .accessibilityValue(value.map { "\(Int($0)) мс" } ?? "нет ответа")
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
