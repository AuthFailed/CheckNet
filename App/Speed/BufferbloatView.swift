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
    var useLiveActivity = true

    var isRunning: Bool { if case .running = phase { true } else { false } }

    /// The phase currently under way, for the "Measuring upload…" label.
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
        let activity = useLiveActivity ? CheckActivityController() : nil
        activity?.start(kind: .bufferbloat, title: "Bufferbloat", subtitle: "Latency under load",
                        view: activityView())
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
                await activity?.update(activityView())
            }
            if isRunning { phase = .idle }   // cancelled before it finished
            await activity?.end(activityView())
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private static func phaseLabel(_ phase: BufferbloatPhase) -> String {
        switch phase {
        case .idle: return "Idle"
        case .download: return "Download"
        case .upload: return "Upload"
        }
    }

    private func activityView() -> CheckActivityView {
        BufferbloatActivityContent.view(
            phaseLabel: activePhase.map(Self.phaseLabel) ?? "",
            latestRTT: samples.last?.rttMillis,
            gradeLetter: result?.grade.letter,
            addedLatency: result?.addedLatency,
            idleRTT: result?.idleRTT,
            loadedRTT: result.map { max($0.downloadRTT, $0.uploadRTT) },
            isRunning: isRunning)
    }
}

struct BufferbloatView: View {
    var autostart = false
    @State private var model = BufferbloatModel()
    @Environment(AppSettings.self) private var settings
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
                    title: "Ready to test bufferbloat",
                    message: "We measure latency at idle, then under full download and upload load. The rise in latency under load is what breaks calls and lags games even on a fast connection."
                )
            }
        } bottom: {
            RunButton(title: "Check", running: model.isRunning) { model.toggle() }
        }
        .animation(.snappy, value: model.phase)
        .haptic(.success, trigger: model.phase) { $0 == .done }
        .haptic(.failure, trigger: model.phase) { if case .failed = $0 { true } else { false } }
        .navigationTitle("Bufferbloat")
        .toolTitleDisplayMode()
        .onDisappear { model.stop() }
        .onAppear {
            model.useLiveActivity = settings.liveActivitiesEnabled
            if autostart, model.phase == .idle { model.start() }
        }
    }

    // MARK: Running

    private var runningCard: some View {
        HStack(spacing: 14) {
            ProgressView()
            VStack(alignment: .leading, spacing: 2) {
                Text(runningLabel).font(.headline)
                Text("Keep the screen open — load in progress").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .card()
    }

    private var runningLabel: LocalizedStringKey {
        switch model.activePhase {
        case .idle: "Measuring idle latency…"
        case .download: "Loading download…"
        case .upload: "Loading upload…"
        case nil: "Testing…"
        }
    }

    // MARK: Grade

    private func gradeCard(_ result: BufferbloatResult) -> some View {
        HStack(spacing: 18) {
            Text(result.grade.letter)
                .font(.system(size: gradeSize, weight: .heavy, design: .rounded))
                .foregroundStyle(gradeColor(result.grade))
                .frame(minWidth: gradeSize + 12)
                .accessibilityLabel("Rating \(result.grade.letter)")
            VStack(alignment: .leading, spacing: 4) {
                Text(gradeVerdict(result.grade)).font(.headline)
                Text("Latency rises by +\(Int(result.addedLatency.rounded())) ms under load")
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
            SectionCaption(text: "Latency over time")
            Chart {
                ForEach(Array(model.samples.enumerated()), id: \.offset) { _, sample in
                    LineMark(
                        x: .value("Seconds", sample.elapsed),
                        y: .value("RTT", sample.rttMillis)
                    )
                    .foregroundStyle(by: .value("Phase", phaseName(sample.phase)))
                    .interpolationMethod(.catmullRom)
                }
                if let idle = model.result?.idleRTT {
                    RuleMark(y: .value("Idle", idle))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(.secondary)
                        .annotation(position: .top, alignment: .leading) {
                            Text("idle").font(.caption2).foregroundStyle(.secondary)
                        }
                }
            }
            .chartForegroundStyleScale([
                phaseName(.idle): Color.secondary,
                phaseName(.download): Color.blue,
                phaseName(.upload): Color.green
            ])
            .chartYAxisLabel("ms")
            .frame(height: chartHeight)
            .padding(14)
            .card()
        }
    }

    // MARK: Numbers

    private func numbersCard(_ result: BufferbloatResult) -> some View {
        VStack(spacing: 0) {
            InfoRow(label: "Idle", value: "\(Int(result.idleRTT.rounded())) ms", mono: true)
            Divider().padding(.leading, 14)
            InfoRow(label: "Under download", value: "\(Int(result.downloadRTT.rounded())) ms", mono: true,
                    valueColor: .blue)
            Divider().padding(.leading, 14)
            InfoRow(label: "Under upload", value: "\(Int(result.uploadRTT.rounded())) ms", mono: true,
                    valueColor: .green)
            Divider().padding(.leading, 14)
            InfoRow(label: "Added under load", value: "+\(Int(result.addedLatency.rounded())) ms", mono: true,
                    valueColor: gradeColor(result.grade))
            if result.downloadMbps != nil || result.uploadMbps != nil {
                Divider().padding(.leading, 14)
                InfoRow(label: "Throughput",
                        value: "↓\(mbps(result.downloadMbps)) · ↑\(mbps(result.uploadMbps)) Mbps", mono: true)
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
        case .idle: "Idle"
        case .download: "Download"
        case .upload: "Upload"
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
        case .a: "Excellent — latency barely rises"
        case .b: "Good — calls and games are stable"
        case .c: "Noticeable — occasional stutter possible"
        case .d: "Bad — video calls will break up"
        case .f: "Very bad — the network chokes under load"
        }
    }
}
