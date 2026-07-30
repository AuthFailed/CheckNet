import SwiftUI

/// Manages saved VPN subscriptions — same idea as saved domains and IPs, but as
/// a separate list: a subscription is not a ping target.
struct SavedSubscriptionsEditor: View {
    @Environment(SavedSubscriptionsStore.self) private var store
    @State private var name = ""
    @State private var value = ""

    var body: some View {
        List {
            Section {
                TextField("Name (optional)", text: $name)
                TextField("URL, happ:// or incy:// link", text: $value, axis: .vertical)
                    .lineLimit(1...3)
                    .font(.callout.monospaced())
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                HStack {
                    Button { if let s = clipboard() { value = s } } label: {
                        Label("Paste", systemImage: "doc.on.clipboard")
                    }
                    Spacer()
                    Button {
                        store.add(name: name, value: value)
                        name = ""; value = ""
                    } label: { Label("Add", systemImage: "plus.circle.fill") }
                        .buttonStyle(.borderedProminent)
                        .disabled(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  || store.contains(value))
                }
            } header: {
                Text("New subscription")
            } footer: {
                if store.contains(value) && !value.isEmpty {
                    Text("This subscription is already saved.")
                }
            }

            Section("Saved") {
                if store.items.isEmpty {
                    ContentUnavailableView("Empty for now", systemImage: "list.bullet.rectangle",
                                           description: Text("Save subscriptions right from \"Subscription parsing\" — they'll appear here and in quick select."))
                } else {
                    ForEach(store.items) { item in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(item.name).font(.callout.weight(.medium))
                                Spacer()
                                Text(item.kind).font(.caption2.weight(.bold))
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(.quaternary, in: Capsule())
                            }
                            Text(item.value).font(.caption.monospaced())
                                .foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
                        }
                        .padding(.vertical, 2)
                    }
                    .onDelete { store.remove(atOffsets: $0) }
                }
            }
        }
        .navigationTitle("VPN subscriptions")
        #if os(iOS)
        .toolbarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        #endif
    }

    private func clipboard() -> String? {
        #if os(iOS)
        return UIPasteboard.general.string
        #elseif os(macOS)
        return NSPasteboard.general.string(forType: .string)
        #else
        return nil
        #endif
    }
}
