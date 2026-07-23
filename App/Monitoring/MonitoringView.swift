import SwiftUI

struct MonitoringView: View {
    @State private var manager = MonitoringManager()
    @State private var newHost = ""

    var body: some View {
        ToolScaffold {
            HStack {
                HostInputBar(text: $newHost, placeholder: "Добавить хост", icon: "plus.circle") {
                    manager.add(newHost); newHost = ""
                } trailing: {
                    AnyView(
                        Button {
                            manager.add(newHost); newHost = ""
                        } label: {
                            Image(systemName: "plus").foregroundStyle(.blue)
                        }
                        .disabled(newHost.trimmingCharacters(in: .whitespaces).isEmpty)
                    )
                }
            }

            if manager.entries.isEmpty {
                ContentUnavailableView("Нет хостов", systemImage: "bell.badge",
                                       description: Text("Добавьте хосты для непрерывного мониторинга и уведомлений о падении."))
                .padding(.top, 40)
            } else {
                statusBanner
                intervalCard
            }
        } content: {
            if !manager.entries.isEmpty {
                hostsCard
            }
        } bottom: {
            if !manager.entries.isEmpty {
                RunButton(title: "Запустить мониторинг", running: manager.isMonitoring) {
                    manager.toggleMonitoring()
                }
            }
        }
        .animation(.snappy, value: manager.entries)
        // Pull to re-check every host now, without waiting for the interval.
        .refreshable { await manager.checkAll() }
        // Monitoring is the one screen people leave running while doing
        // something else, so a host going down is worth feeling.
        .haptic(.failure, trigger: manager.entries.filter { $0.status == .down }.count) { $0 > 0 }
        .navigationTitle("Мониторинг")
        .toolTitleDisplayMode()
    }

    private var statusBanner: some View {
        let down = manager.entries.filter { $0.status == .down }.count
        return HStack(spacing: 10) {
            Image(systemName: manager.isMonitoring ? "dot.radiowaves.left.and.right" : "pause.circle")
                .foregroundStyle(manager.isMonitoring ? .green : .secondary)
            Text(manager.isMonitoring ? LocalizedStringKey("Мониторинг активен") : LocalizedStringKey("Остановлен"))
                .font(.subheadline.weight(.medium))
            Spacer()
            if down > 0 {
                Text("\(down) недоступно").font(.caption.weight(.semibold)).foregroundStyle(.red)
            }
        }
        .padding(14).card()
    }

    private var hostsCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(manager.entries.enumerated()), id: \.element.id) { idx, entry in
                HStack(spacing: 12) {
                    StatusDot(level: .init(entry.status), label: LocalizedStringKey(StatusStyle.label(entry.status)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.host).font(.callout.weight(.medium))
                        if let checked = entry.lastChecked {
                            Text("проверено \(checked, style: .relative) назад")
                                .font(.caption2).foregroundStyle(.secondary)
                        } else {
                            Text("ожидание…").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Group {
                            if entry.status == .down {
                                Text("недоступен")
                            } else {
                                Text(entry.lastLatency.map { "\(Int($0)) мс" } ?? "—")
                            }
                        }
                        .font(.callout.monospaced())
                        .foregroundStyle(StatusStyle.color(entry.status))
                        if entry.status != .down && entry.lossPercent > 0 {
                            Text("\(Int(entry.lossPercent))% потерь").font(.caption2).foregroundStyle(.orange)
                        }
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 11)
                .contextMenu {
                    Button("Удалить", role: .destructive) {
                        if let index = manager.entries.firstIndex(where: { $0.id == entry.id }) {
                            manager.remove(at: IndexSet(integer: index))
                        }
                    }
                }
                if idx < manager.entries.count - 1 { Divider().padding(.leading, 36) }
            }
        }
        .card()
    }

    private var intervalCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Интервал проверки")
                Spacer()
                Text("\(Int(manager.intervalSeconds)) с").monospaced().foregroundStyle(.secondary)
            }
            Slider(value: $manager.intervalSeconds, in: 15...300, step: 15)
            if !manager.notificationsAuthorized {
                Text("Уведомления о падении будут запрошены при запуске.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(14).card()
    }
}
