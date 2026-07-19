import SwiftUI

/// A reusable host/IP input card with an icon and optional trailing accessory.
struct HostInputBar: View {
    @Binding var text: String
    var placeholder: String = "Хост или IP"
    var icon: String = "globe"
    var disabled: Bool = false
    var onSubmit: () -> Void = {}
    var trailing: () -> AnyView = { AnyView(EmptyView()) }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .font(.system(size: 19))
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 17))
                .submitLabel(.go)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                #endif
                .onSubmit(onSubmit)
                .disabled(disabled)
            trailing()
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 52)
        .card()
    }
}

/// A primary action button pinned to the bottom safe area.
struct RunButton: View {
    var title: String
    var running: Bool
    var disabled: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(running ? "Остановить" : title, systemImage: running ? "stop.fill" : "play.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .foregroundStyle(running ? .red : .white)
                .background(running ? AnyShapeStyle(Color.red.opacity(0.14)) : AnyShapeStyle(Color.blue),
                            in: RoundedRectangle(cornerRadius: 15))
        }
        .disabled(disabled)
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.bar)
    }
}

/// A small labeled section header used above cards.
struct SectionCaption: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }
}

/// A key/value row rendered inside a card.
struct InfoRow: View {
    let label: String
    let value: String
    var mono: Bool = false
    var valueColor: Color = .primary

    var body: some View {
        HStack(alignment: .top) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing)
                .font(mono ? .system(.callout, design: .monospaced) : .callout)
                .textSelection(.enabled)
        }
        .font(.callout)
        .padding(.horizontal, 14).padding(.vertical, 11)
    }
}
