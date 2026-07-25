import SwiftUI

/// Управление сохранёнными подписками VPN — тот же принцип, что у сохранённых
/// доменов и IP, но отдельным списком: подписка не является целью для пинга.
struct SavedSubscriptionsEditor: View {
    @Environment(SavedSubscriptionsStore.self) private var store
    @State private var name = ""
    @State private var value = ""

    var body: some View {
        List {
            Section {
                TextField("Название (необязательно)", text: $name)
                TextField("URL, happ:// или incy:// ссылка", text: $value, axis: .vertical)
                    .lineLimit(1...3)
                    .font(.callout.monospaced())
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                HStack {
                    Button { if let s = clipboard() { value = s } } label: {
                        Label("Вставить", systemImage: "doc.on.clipboard")
                    }
                    Spacer()
                    Button {
                        store.add(name: name, value: value)
                        name = ""; value = ""
                    } label: { Label("Добавить", systemImage: "plus.circle.fill") }
                        .buttonStyle(.borderedProminent)
                        .disabled(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                  || store.contains(value))
                }
            } header: {
                Text("Новая подписка")
            } footer: {
                if store.contains(value) && !value.isEmpty {
                    Text("Такая подписка уже сохранена.")
                }
            }

            Section("Сохранённые") {
                if store.items.isEmpty {
                    ContentUnavailableView("Пока пусто", systemImage: "list.bullet.rectangle",
                                           description: Text("Сохраняйте подписки прямо из «Парсинга подписки» — они появятся здесь и в быстром выборе."))
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
        .navigationTitle("Подписки VPN")
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
