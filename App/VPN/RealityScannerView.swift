import SwiftUI
import NetworkKit

@MainActor
@Observable
final class RealityScannerModel {
    var target = ""
    var requireH2 = false
    private(set) var isRunning = false
    private(set) var hits: [RealityScanHit] = []
    private(set) var scanned = 0
    private(set) var total = 0
    private(set) var errorMessage: String?
    private var task: Task<Void, Never>?
    var useLiveActivity = true

    func toggle() { isRunning ? stop() : start() }

    func start() {
        let t = target.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        stop()
        hits = []; scanned = 0; total = 0; errorMessage = nil; isRunning = true
        let requireH2 = requireH2
        let activity = useLiveActivity ? CheckActivityController() : nil
        activity?.start(kind: .ipScan, title: t, subtitle: "Reality-скан", view: activityView())
        task = Task { [weak self] in
            guard let self else { return }
            for await event in RealityScanner().scan(target: t, requireH2: requireH2) {
                if Task.isCancelled { break }
                switch event {
                case .progress(let s, let total):
                    scanned = s; self.total = total
                case .hit(let h):
                    hits.append(h)
                    hits.sort { (IPv4Range.toUInt32($0.ip) ?? 0) < (IPv4Range.toUInt32($1.ip) ?? 0) }
                case .finished:
                    break
                case .failed(let reason):
                    errorMessage = reason
                }
                await activity?.update(activityView())
            }
            isRunning = false
            await activity?.end(activityView())
        }
    }

    func stop() { task?.cancel(); task = nil; isRunning = false }

    private func activityView() -> CheckActivityView {
        ScanActivityContent.view(foundLabel: "Найдено", found: hits.count,
                                 scanned: scanned, total: total, isRunning: isRunning)
    }
}

/// Сканер доменов для Reality (#79). Обходит IP/подсеть, к каждому адресу делает
/// TLS 1.3-хендшейк без SNI и показывает найденные домены-кандидаты под `dest`
/// (по образцу `XTLS/RealiTLScanner`). Только диагностика — помогает найти
/// камуфляжный домен рядом со своим сервером, не обходит блокировки.
struct RealityScannerView: View {
    var autostart = false
    @State private var model = RealityScannerModel()
    @Environment(AppSettings.self) private var settings
    @State private var showConsent = false
    @State private var consented = false

    private func requestStart() {
        if settings.confirmSensitiveTests && !consented {
            showConsent = true
        } else {
            model.start()
        }
    }

    var body: some View {
        ToolScaffold {
            HostInputBar(text: $model.target, placeholder: "IP, CIDR или домен",
                         icon: "dot.radiowaves.left.and.right", disabled: model.isRunning) {
                requestStart()
            }

            Toggle(isOn: $model.requireH2) {
                Label("Только с HTTP/2", systemImage: "bolt.horizontal")
            }
            .disabled(model.isRunning)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .card()

            if let error = model.errorMessage {
                ErrorCard(message: error) { requestStart() }
            } else if model.total > 0 {
                progressCard
            }
        } content: {
            if !model.hits.isEmpty {
                hitsCard
            } else if !model.isRunning && model.scanned > 0 {
                Text("Подходящих доменов не найдено")
                    .foregroundStyle(.secondary).padding(.top, 24)
            } else if !model.isRunning, model.errorMessage == nil {
                ToolIdleHint(
                    icon: "dot.radiowaves.left.and.right",
                    title: "Поиск доменов для Reality",
                    message: "Обойдём диапазон и покажем адреса с TLS 1.3 и их домен из сертификата — кандидаты под dest.",
                    example: "8.8.8.0/28",
                    current: model.target
                ) { model.target = "8.8.8.0/28" }
            }
        } bottom: {
            RunButton(title: "Сканировать", running: model.isRunning,
                      disabled: model.target.trimmingCharacters(in: .whitespaces).isEmpty) {
                if model.isRunning { model.stop() } else { requestStart() }
            }
        }
        .animation(.snappy, value: model.hits)
        .haptic(.success, trigger: model.isRunning) { !$0 && model.errorMessage == nil }
        .haptic(.failure, trigger: model.isRunning) { !$0 && model.errorMessage != nil }
        .navigationTitle("Сканер для Reality")
        .toolTitleDisplayMode()
        .confirmationDialog("Запустить сканер?", isPresented: $showConsent, titleVisibility: .visible) {
            Button("Понимаю, запустить") { consented = true; model.start() }
            Button("Запускать без подтверждений") { settings.disableSensitivePrompts(); model.start() }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Сканер обходит диапазон адресов и делает TLS-рукопожатие к каждому. Некоторые сети считают это подозрительной активностью — сканируйте только адреса, к которым имеете отношение.")
        }
        .onAppear {
            model.useLiveActivity = settings.liveActivitiesEnabled
            if autostart { requestStart() }
        }
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(model.hits.count) найдено").font(.headline).foregroundStyle(.green)
                Spacer()
                Text("\(model.scanned) / \(model.total)")
                    .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            ProgressView(value: Double(model.scanned), total: Double(max(model.total, 1))).tint(.blue)
        }
        .padding(14).card()
    }

    private var hitsCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(model.hits.enumerated()), id: \.element.id) { idx, hit in
                HStack(spacing: 12) {
                    StatusDot(level: hit.supportsH2 ? .ok : .warning,
                              label: hit.supportsH2 ? "TLS 1.3 + h2" : "TLS 1.3")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hit.domain)
                            .font(.callout.weight(.medium)).textSelection(.enabled).lineLimit(1)
                        Text("\(hit.ip) · \(hit.issuer)")
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    if hit.supportsH2 {
                        Text("h2").font(.caption2.weight(.semibold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(.green.opacity(0.14), in: Capsule())
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                if idx < model.hits.count - 1 { Divider().padding(.leading, 40) }
            }
        }
        .card()
    }
}
