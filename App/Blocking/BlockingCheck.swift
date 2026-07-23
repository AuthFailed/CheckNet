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

    /// The UI-free counterpart in NetworkKit that owns dispatch and defaults.
    /// Raw values are identical, so the mapping is total.
    var kind: CensorshipCheckKind { CensorshipCheckKind(rawValue: rawValue)! }

    /// Whether the check accepts a target host/domain.
    var needsTarget: Bool { kind.needsTarget }

    var defaultTarget: String { kind.defaultTarget }

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
        await kind.run(target: target)
    }
}

struct BlockingCheckView: View {
    let check: BlockingCheck
    @Environment(WebhookSettings.self) private var webhooks
    @State private var target: String
    @State private var run = ToolRunModel<CensorshipFinding>()
    @State private var showWebhookFields = false
    @State private var showSchedule = false
    /// The evidence bullet grows with text size instead of sitting at 5 pt.
    @ScaledMetric(relativeTo: .caption) private var bulletSize: CGFloat = 6

    init(check: BlockingCheck) {
        self.check = check
        _target = State(initialValue: check.defaultTarget)
    }

    private func start() {
        guard !run.isRunning else { return }
        let check = check, target = target
        run.start {
            await check.run(target: target)
        } onSuccess: { finding in
            WebhookReporter.reportBlocking(check: check.rawValue, target: target, finding: finding)
        }
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
                HostInputBar(text: $target, placeholder: "Домен для проверки",
                             icon: check.systemImage, disabled: run.isRunning,
                             savedHostTool: .dnsTamper) {
                    start()
                }
            }

            if let finding = run.value {
                verdictCard(finding)
            } else if run.isRunning {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Проверяем ваше соединение…").font(.caption).foregroundStyle(.secondary)
                }
                .padding(.top, 40)
            }
        } content: {
            if let finding = run.value, !finding.evidence.isEmpty {
                evidenceCard(finding)
            }
        } bottom: {
            RunButton(title: "Проверить", running: run.isRunning,
                      disabled: check.needsTarget && target.trimmingCharacters(in: .whitespaces).isEmpty) {
                if run.isRunning { return }
                start()
            }
        }
        .animation(.snappy, value: run.value?.verdict)
        // A restriction is not an error but it is the answer people came for,
        // so it gets the warning pattern rather than the success one.
        .haptic(.warning, trigger: run.value?.verdict) { $0 == .restricted }
        .haptic(.success, trigger: run.value?.verdict) { $0 == .clean }
        .navigationTitle(LocalizedStringKey(check.title))
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
                            let target = target.trimmingCharacters(in: .whitespaces)
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
                        Image(systemName: "circle.fill").font(.system(size: bulletSize)).foregroundStyle(.tertiary).padding(.top, 6).accessibilityHidden(true)
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
