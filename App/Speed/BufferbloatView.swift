import SwiftUI
import Charts
import NetworkKit

@MainActor
@Observable
final class BufferbloatModel {
    enum Phase: Equatable { case idle, running(BufferbloatPhase), done, failed(String) }

    private(set) var phase: Phase = .idle
    private(set) var samples: [BufferbloatSample] = []
    private(set) var result: BufferbloatResult?
    private var task: Task<Void, Never>?

    var isRunning: Bool { if case .running = phase { true } else { false } }

    /// The phase currently under way, for the "Измеряем отдачу…" label.
    var activePhase: BufferbloatPhase? {
        if case .running(let p) = phase { return p }
        return nil
    }

    func toggle() { isRunning ? stop() : start() }

    func start() {
        stop()
        samples = []
        result = nil
        phase = .running(.idle)
        task = Task { [weak self] in
            guard let self else { return }
            for await event in BufferbloatTest().run() {
                if Task.isCancelled { break }
                switch event {
                case .phase(let p): phase = .running(p)
                case .sample(let s): samples.append(s)
                case .finished(let r): result = r; phase = .done
                case .failed(let reason): phase = .failed(reason)
                }
            }
            if isRunning { phase = .idle }   // cancelled before it finished
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}

struct BufferbloatView: View {
    var autostart = false
    @State private var model = BufferbloatModel()
    @ScaledMetric(relativeTo: .body) private var chartHeight: CGFloat = 150
    @ScaledMetric(relativeTo: .largeTitle) private var gradeSize: CGFloat = 64

    var body: some View {
        ToolScaffold {
            switch model.phase {
            case .done:
                if let result = model.result { gradeCard(result) }
            case .running:
                runningCard
            case .failed(let msg):
                ErrorCard(message: msg) { model.start() }
            case .idle:
                EmptyView()
            }
        } content: {
            if !model.samples.isEmpty {
                chartCard
            }
            if let result = model.result {
                numbersCard(result)
            }
            if model.phase == .idle {
                ToolIdleHint(
                    icon: "waveform.path.ecg",
                    title: "Готово к проверке bufferbloat",
                    message: "Замерим задержку в простое, затем под полной загрузкой и отдачей. Рост задержки под нагрузкой — то, из-за чего рвутся звонки и лагают игры при быстром интернете."
                )
            }
        } bottom: {
            RunButton(title: "Проверить", running: model.isRunning) { model.toggle() }
        }
        .animation(.snappy, value: model.phase)
        .haptic(.success, trigger: model.phase) { $0 == .done }
        .haptic(.failure, trigger: model.phase) { if case .failed = $0 { true } else { false } }
        .navigationTitle("Bufferbloat")
        .toolTitleDisplayMode()
        .onDisappear { model.stop() }
        .onAppear { if autostart, model.phase == .idle { model.start() } }
    }

    // MARK: Running

    private var runningCard: some View {
        HStack(spacing: 14) {
            ProgressView()
            VStack(alignment: .leading, spacing: 2) {
                Text(runningLabel).font(.headline)
                Text("Не закрывайте экран — идёт нагрузка").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .card()
    }

    private var runningLabel: LocalizedStringKey {
        switch model.activePhase {
        case .idle: "Замеряем задержку в простое…"
        case .download: "Нагружаем загрузку…"
        case .upload: "Нагружаем отдачу…"
        case nil: "Проверяем…"
        }
    }

    // MARK: Grade

    private func gradeCard(_ result: BufferbloatResult) -> some View {
        HStack(spacing: 18) {
            Text(result.grade.letter)
                .font(.system(size: gradeSize, weight: .heavy, design: .rounded))
                .foregroundStyle(gradeColor(result.grade))
                .frame(minWidth: gradeSize + 12)
                .accessibilityLabel("Оценка \(result.grade.letter)")
            VStack(alignment: .leading, spacing: 4) {
                Text(gradeVerdict(result.grade)).font(.headline)
                Text("Задержка растёт на +\(Int(result.addedLatency.rounded())) мс под нагрузкой")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(18)
        .card()
    }

    // MARK: Chart

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionCaption(text: "Задержка во времени")
            Chart {
                ForEach(Array(model.samples.enumerated()), id: \.offset) { _, sample in
                    LineMark(
                        x: .value("Секунды", sample.elapsed),
                        y: .value("RTT", sample.rttMillis)
                    )
                    .foregroundStyle(by: .value("Фаза", phaseName(sample.phase)))
                    .interpolationMethod(.catmullRom)
                }
                if let idle = model.result?.idleRTT {
                    RuleMark(y: .value("Простой", idle))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(.secondary)
                        .annotation(position: .top, alignment: .leading) {
                            Text("простой").font(.caption2).foregroundStyle(.secondary)
                        }
                }
            }
            .chartForegroundStyleScale([
                phaseName(.idle): Color.secondary,
                phaseName(.download): Color.blue,
                phaseName(.upload): Color.green
            ])
            .chartYAxisLabel("мс")
            .frame(height: chartHeight)
            .padding(14)
            .card()
        }
    }

    // MARK: Numbers

    private func numbersCard(_ result: BufferbloatResult) -> some View {
        VStack(spacing: 0) {
            InfoRow(label: "Простой", value: "\(Int(result.idleRTT.rounded())) мс", mono: true)
            Divider().padding(.leading, 14)
            InfoRow(label: "Под загрузкой", value: "\(Int(result.downloadRTT.rounded())) мс", mono: true,
                    valueColor: .blue)
            Divider().padding(.leading, 14)
            InfoRow(label: "Под отдачей", value: "\(Int(result.uploadRTT.rounded())) мс", mono: true,
                    valueColor: .green)
            Divider().padding(.leading, 14)
            InfoRow(label: "Прирост под нагрузкой", value: "+\(Int(result.addedLatency.rounded())) мс", mono: true,
                    valueColor: gradeColor(result.grade))
            if result.downloadMbps != nil || result.uploadMbps != nil {
                Divider().padding(.leading, 14)
                InfoRow(label: "Пропускная способность",
                        value: "↓\(mbps(result.downloadMbps)) · ↑\(mbps(result.uploadMbps)) Мбит/с", mono: true)
            }
        }
        .card()
    }

    private func mbps(_ value: Double?) -> String {
        guard let value, value > 0 else { return "—" }
        return String(Int(value.rounded()))
    }

    // MARK: Styling

    private func phaseName(_ phase: BufferbloatPhase) -> String {
        switch phase {
        case .idle: "Простой"
        case .download: "Загрузка"
        case .upload: "Отдача"
        }
    }

    private func gradeColor(_ grade: BufferbloatGrade) -> Color {
        switch grade {
        case .a: .green
        case .b: .mint
        case .c: .yellow
        case .d: .orange
        case .f: .red
        }
    }

    private func gradeVerdict(_ grade: BufferbloatGrade) -> LocalizedStringKey {
        switch grade {
        case .a: "Отлично — задержка почти не растёт"
        case .b: "Хорошо — звонки и игры стабильны"
        case .c: "Заметно — возможны подлагивания"
        case .d: "Плохо — видеозвонки будут рваться"
        case .f: "Очень плохо — сеть захлёбывается под нагрузкой"
        }
    }
}
