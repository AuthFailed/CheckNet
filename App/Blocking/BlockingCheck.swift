import SwiftUI
import NetworkKit

/// The censorship / local-restriction checks shown in the Блокировки tab.
enum BlockingCheck: String, CaseIterable, Identifiable {
    case dnsSpoofing, httpBlock, sniBlocking, ipBlocking, whitelist, siberian, transferCutoff

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dnsSpoofing: return "Подмена DNS"
        case .httpBlock: return "Страница-заглушка"
        case .sniBlocking: return "Блокировка по SNI"
        case .ipBlocking: return "Блокировка по IP"
        case .whitelist: return "Белые списки"
        case .siberian: return "«Сибирская» блокировка"
        case .transferCutoff: return "Обрыв на 16–20 КБ"
        }
    }

    var subtitle: String {
        switch self {
        case .dnsSpoofing: return "ISP подменяет DNS-ответы"
        case .httpBlock: return "Вставка страницы «Доступ ограничен»"
        case .sniBlocking: return "DPI рвёт TLS по имени сайта"
        case .ipBlocking: return "IP закрыт на уровне сети"
        case .whitelist: return "Доступны только «разрешённые» сайты"
        case .siberian: return "Троттлинг параллельных TLS"
        case .transferCutoff: return "Передача замирает на середине"
        }
    }

    var systemImage: String {
        switch self {
        case .dnsSpoofing: return "exclamationmark.shield"
        case .httpBlock: return "doc.text.magnifyingglass"
        case .sniBlocking: return "lock.trianglebadge.exclamationmark"
        case .ipBlocking: return "network.slash"
        case .whitelist: return "list.bullet.rectangle"
        case .siberian: return "snowflake"
        case .transferCutoff: return "pause.circle"
        }
    }

    /// Whether the check accepts a target host/domain.
    var needsTarget: Bool { self != .whitelist }

    var defaultTarget: String {
        switch self {
        case .dnsSpoofing, .httpBlock: return "rutracker.org"
        case .sniBlocking, .siberian: return "www.tor-project.org"
        case .ipBlocking: return "x.com"
        case .whitelist: return ""
        case .transferCutoff: return TransferCutoffCheck.defaultTarget
        }
    }

    var explanation: String {
        switch self {
        case .dnsSpoofing:
            return "Сравниваем ответ вашего DNS с доверенным DoH-резолвером (1.1.1.1). Если адреса различаются или ваш провайдер вернул чужой/приватный адрес — это подмена DNS."
        case .httpBlock:
            return "Запрашиваем сайт по HTTP и ищем в ответе маркеры страницы блокировки («Доступ ограничен», «Роскомнадзор», 149-ФЗ)."
        case .sniBlocking:
            return "Открываем TLS к одному и тому же IP с «запрещённым» именем и с контрольным. Если рвётся только «запрещённое» — это DPI-фильтрация по SNI."
        case .ipBlocking:
            return "Подключаемся напрямую к реальному IP сайта и к контрольному адресу. Если цель недоступна, а контроль доступен — IP заблокирован."
        case .whitelist:
            return "Проверяем доступность «разрешённых» ресурсов (Госуслуги, Яндекс, VK) и зарубежных контролей. Если работают только первые — вероятен режим белого списка при региональном шатдауне."
        case .siberian:
            return "Открываем много параллельных TLS-соединений к одному хосту. Если часть срывается — это троттлинг по числу TLS-сессий, характерный для некоторых операторов."
        case .transferCutoff:
            return "Соединения с зарубежными серверами часто замирают, когда передача расходится — обычно в районе 16–20 КБ. Проверяем тремя способами: наращиваем объём по 4 КБ, отправляем крошечный запрос множеством мелких пакетов и его же одним пакетом. Если мелкими пакетами замирает, а одним проходит — считаются пакеты, а не килобайты. Для сравнения та же проба идёт к российскому серверу."
        }
    }

    func run(target: String) async -> CensorshipFinding {
        let checks = CensorshipChecks()
        let host = target.trimmingCharacters(in: .whitespaces)
        switch self {
        case .dnsSpoofing: return await checks.checkDNSSpoofing(domain: host)
        case .httpBlock:   return await checks.checkHTTPBlockPage(domain: host)
        case .sniBlocking: return await checks.checkSNIBlocking(blockedDomain: host)
        case .ipBlocking:  return await checks.checkIPBlocking(domain: host)
        case .whitelist:   return await checks.checkWhitelistMode()
        case .siberian:    return await checks.checkSiberianBlock(host: host)
        case .transferCutoff: return await TransferCutoffCheck().run(target: host)
        }
    }
}

@MainActor
@Observable
final class BlockingCheckModel {
    let check: BlockingCheck
    var target: String
    private(set) var isRunning = false
    private(set) var finding: CensorshipFinding?

    init(check: BlockingCheck) {
        self.check = check
        self.target = check.defaultTarget
    }

    func run() async {
        isRunning = true; finding = nil
        let result = await check.run(target: target)
        finding = result
        isRunning = false
        WebhookReporter.reportBlocking(check: check.rawValue, target: target, finding: result)
    }
}

struct BlockingCheckView: View {
    let check: BlockingCheck
    @Environment(WebhookSettings.self) private var webhooks
    @State private var model: BlockingCheckModel
    @State private var showWebhookFields = false
    @State private var showSchedule = false

    init(check: BlockingCheck) {
        self.check = check
        _model = State(initialValue: BlockingCheckModel(check: check))
    }

    var body: some View {
        ToolScaffold {
            Text(LocalizedStringKey(check.explanation))
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .card()

            if check.needsTarget {
                HostInputBar(text: $model.target, placeholder: "Домен для проверки",
                             icon: check.systemImage, disabled: model.isRunning,
                             savedHostTool: .dnsTamper) {
                    Task { await model.run() }
                }
            }

            if let finding = model.finding {
                verdictCard(finding)
                if !finding.evidence.isEmpty { evidenceCard(finding) }
            } else if model.isRunning {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Проверяем ваше соединение…").font(.caption).foregroundStyle(.secondary)
                }
                .padding(.top, 40)
            }
        } bottom: {
            RunButton(title: "Проверить", running: model.isRunning,
                      disabled: check.needsTarget && model.target.trimmingCharacters(in: .whitespaces).isEmpty) {
                if model.isRunning { return }
                Task { await model.run() }
            }
        }
        .animation(.snappy, value: model.finding?.verdict)
        .navigationTitle(check.title)
        .toolTitleDisplayMode()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showSchedule = true } label: {
                    Image(systemName: "clock.arrow.2.circlepath").accessibilityLabel("Расписание")
                }
            }
            if webhooks.isEnabled {
                ToolbarItem(placement: .primaryAction) {
                    Button { showWebhookFields = true } label: {
                        Image(systemName: "paperplane").accessibilityLabel("Данные вебхука")
                    }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                InfoButton(title: check.title, systemImage: check.systemImage, message: check.explanation)
            }
        }
        .sheet(isPresented: $showWebhookFields) {
            NavigationStack { WebhookFieldsView(schema: WebhookCatalog.blocking) }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showSchedule) {
            NavigationStack {
                Form {
                    SchedulingSection(
                        makeKind: {
                            let target = model.target.trimmingCharacters(in: .whitespaces)
                            let host = target.isEmpty ? check.defaultTarget : target
                            return .blocking(checkID: check.rawValue, target: host)
                        },
                        matches: { task in
                            if case .blocking(let id, _) = task.kind { return id == check.rawValue }
                            return false
                        }
                    )
                }
                .navigationTitle("Расписание · \(check.title)")
                #if os(iOS)
                .toolbarTitleDisplayMode(.inline)
                #endif
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { showSchedule = false } } }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private func verdictCard(_ finding: CensorshipFinding) -> some View {
        let (color, symbol) = style(finding.verdict)
        return HStack(spacing: 14) {
            Image(systemName: symbol).font(.largeTitle).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(finding.headline)).font(.headline)
                Text(LocalizedStringKey(finding.detail)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16).card()
    }

    private func evidenceCard(_ finding: CensorshipFinding) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionCaption(text: "Данные проверки")
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(finding.evidence.enumerated()), id: \.offset) { idx, line in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "circle.fill").font(.system(size: 5)).foregroundStyle(.tertiary).padding(.top, 6)
                        Text(line).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        Spacer()
                    }
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    if idx < finding.evidence.count - 1 { Divider().padding(.leading, 28) }
                }
            }
            .card()
        }
    }

    private func style(_ verdict: CensorshipVerdict) -> (Color, String) {
        switch verdict {
        case .clean: return (.green, "checkmark.shield.fill")
        case .restricted: return (.red, "exclamationmark.shield.fill")
        case .inconclusive: return (.orange, "questionmark.circle.fill")
        }
    }
}
