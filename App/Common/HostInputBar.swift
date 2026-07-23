import SwiftUI

/// A reusable host/IP input card with an icon and optional trailing accessory.
/// Pass `savedHostTool` to surface the saved hosts/domains bookmark menu, so any
/// tool that takes a host or IP can reuse the user's saved targets.
struct HostInputBar: View {
    @Binding var text: String
    var placeholder: String = "Хост или IP"
    var icon: String = "globe"
    var disabled: Bool = false
    var savedHostTool: Tool? = nil
    var onSubmit: () -> Void = {}
    var trailing: () -> AnyView = { AnyView(EmptyView()) }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .font(.title3)
                .accessibilityHidden(true)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.body)
                .submitLabel(.go)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                #endif
                .onSubmit(onSubmit)
                .disabled(disabled)
            trailing()
            if let savedHostTool, !disabled {
                SavedHostsMenu(tool: savedHostTool, text: $text)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 52)
        .card()
    }
}

/// Bookmark menu listing the user's saved hosts (global + tool-scoped) plus a
/// one-tap action to save the current value. Shared by every host-input tool.
struct SavedHostsMenu: View {
    let tool: Tool
    @Binding var text: String
    @Environment(SavedHostsStore.self) private var savedHosts

    var body: some View {
        Menu {
            let hosts = savedHosts.hosts(for: tool)
            if !hosts.isEmpty {
                Section("Сохранённые") {
                    ForEach(hosts) { h in
                        Button {
                            text = h.value
                        } label: {
                            Label(h.name == h.value ? h.value : "\(h.name) · \(h.value)",
                                  systemImage: SavedHostsStore.isIP(h.value) ? "number" : "globe")
                        }
                    }
                }
            }
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            let saveTitle: LocalizedStringKey = trimmed.isEmpty ? "Сохранить хост…" : "Сохранить «\(trimmed)»"
            Button {
                savedHosts.add(name: "", value: trimmed, tool: nil)
            } label: {
                Label(saveTitle, systemImage: "plus")
            }
            .disabled(trimmed.isEmpty)
        } label: {
            Image(systemName: "bookmark.fill")
                .font(.subheadline)
                .foregroundStyle(.blue)
                .padding(7)
                .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
        }
        .accessibilityLabel("Сохранённые хосты")
    }
}

/// A primary action button pinned to the bottom safe area.
struct RunButton: View {
    var title: LocalizedStringKey
    var running: Bool
    var disabled: Bool = false
    var action: () -> Void
    #if os(iOS)
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif

    /// In landscape on a phone the screen is ~390 pt tall, and a 52 pt button
    /// with 10 pt of padding above and below eats a fifth of it. The control
    /// shrinks to the 44 pt minimum tap target there instead of keeping a size
    /// tuned for portrait.
    private var isShort: Bool {
        #if os(iOS)
        verticalSizeClass == .compact
        #else
        false
        #endif
    }

    var body: some View {
        Button(action: action) {
            Label(running ? LocalizedStringKey("Остановить") : title, systemImage: running ? "stop.fill" : "play.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(minHeight: isShort ? 44 : 52)
                .foregroundStyle(running ? .red : .white)
                .background(running ? AnyShapeStyle(Color.red.opacity(0.14)) : AnyShapeStyle(Color.blue),
                            in: RoundedRectangle(cornerRadius: 15))
        }
        .disabled(disabled)
        // Stable hook for UI tests: the visible label is translated into 13
        // languages, so matching on it would only pass in Russian.
        .accessibilityIdentifier("tool.runButton")
        // The bar spans the window, but the control inside it follows the same
        // width cap as the content above — a 1300 pt wide button on an iPad
        // reads as a layout bug, not as emphasis.
        .frame(maxWidth: ToolLayout.contentWidth)
        #if os(macOS)
        // The primary action of the window: Enter runs the check from anywhere,
        // which is what the Return key does in every other Mac app.
        .keyboardShortcut(.defaultAction)
        #endif
        .padding(.horizontal, 16)
        .padding(.vertical, isShort ? 5 : 10)
        .frame(maxWidth: .infinity)
        // A bar, not a card: it spans the window and is separated by a rule.
        // `.bar` alone rendered as a grey slab floating inside the content inset.
        .background(alignment: .top) {
            VStack(spacing: 0) {
                Divider()
                Rectangle().fill(.bar)
            }
        }
    }
}

/// A small labeled section header used above cards.
struct SectionCaption: View {
    let text: String
    var body: some View {
        Text(LocalizedStringKey(text))
            .textCase(.uppercase)
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
            Text(LocalizedStringKey(label)).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(LocalizedStringKey(value))
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing)
                .font(mono ? .system(.callout, design: .monospaced) : .callout)
                .textSelection(.enabled)
        }
        .font(.callout)
        .padding(.horizontal, 14).padding(.vertical, 11)
    }
}
