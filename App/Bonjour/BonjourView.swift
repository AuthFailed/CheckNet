import SwiftUI
import NetworkKit

@MainActor
@Observable
final class BonjourModel {
    private(set) var isRunning = false
    private(set) var services: [BonjourService] = []
    private var task: Task<Void, Never>?

    func toggle() { isRunning ? stop() : start() }

    func start() {
        stop()
        services = []; isRunning = true
        task = Task { [weak self] in
            guard let self else { return }
            for await event in BonjourBrowser().browse(duration: 8.0) {
                if Task.isCancelled { break }
                switch event {
                case .found(let svc):
                    if !services.contains(svc) {
                        services.append(svc)
                        services.sort { $0.type < $1.type }
                    }
                case .removed(let svc):
                    services.removeAll { $0 == svc }
                case .finished:
                    break
                }
            }
            isRunning = false
        }
    }

    func stop() { task?.cancel(); task = nil; isRunning = false }

    var grouped: [(type: String, label: String, services: [BonjourService])] {
        let groups = Dictionary(grouping: services, by: \.type)
        return groups.keys.sorted().map { key in
            let items = groups[key] ?? []
            return (key, items.first?.friendlyType ?? key, items.sorted { $0.name < $1.name })
        }
    }
}

struct BonjourView: View {
    @State private var model = BonjourModel()

    var body: some View {
        ToolScaffold {
            if model.isRunning {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Поиск сервисов mDNS…").foregroundStyle(.secondary)
                    Spacer()
                    Text("\(model.services.count)").font(.headline).foregroundStyle(.blue)
                }
                .padding(14).card()
            }

            if model.services.isEmpty && !model.isRunning {
                ContentUnavailableView(
                    "Нет сервисов",
                    systemImage: "bonjour",
                    description: Text("Запустите поиск, чтобы найти устройства и сервисы Bonjour в сети.")
                )
                .padding(.top, 40)
            }
        } content: {
            ForEach(model.grouped, id: \.type) { group in
                groupCard(group)
            }
        } bottom: {
            RunButton(title: "Искать сервисы", running: model.isRunning) { model.toggle() }
        }
        .animation(.snappy, value: model.services)
        .navigationTitle("Bonjour / mDNS")
        .toolTitleDisplayMode()
    }

    private func groupCard(_ group: (type: String, label: String, services: [BonjourService])) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionCaption(text: "\(group.label) · \(group.type)")
            VStack(spacing: 0) {
                ForEach(Array(group.services.enumerated()), id: \.element.id) { idx, svc in
                    HStack {
                        Image(systemName: "wifi.router").foregroundStyle(.blue)
                        Text(svc.name).font(.callout).lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    if idx < group.services.count - 1 { Divider().padding(.leading, 44) }
                }
            }
            .card()
        }
    }
}
