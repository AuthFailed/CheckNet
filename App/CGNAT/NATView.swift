import SwiftUI
import NetworkKit

@MainActor
@Observable
final class NATModel {
    private(set) var isRunning = false
    private(set) var report: NATReport?

    func run() async {
        isRunning = true; report = nil
        report = await NATDetector().detect()
        isRunning = false
    }
}

struct NATView: View {
    var autostart = false
    @State private var model = NATModel()

    var body: some View {
        ToolScaffold {
            if let report = model.report {
                typeCard(report)
            } else if model.isRunning {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Анализ маршрута и внешнего адреса…").font(.caption).foregroundStyle(.secondary)
                }
                .padding(.top, 60)
            } else {
                ContentUnavailableView("Проверка NAT", systemImage: "arrow.triangle.branch",
                                       description: Text("Определим тип NAT, внешний адрес и наличие CGNAT."))
                .padding(.top, 40)
            }
        } content: {
            if let report = model.report {
                addressCard(report)
                if !report.findings.isEmpty { findingsCard(report) }
            }
        } bottom: {
            RunButton(title: "Проверить NAT", running: model.isRunning) {
                if model.isRunning { return }; Task { await model.run() }
            }
        }
        .animation(.snappy, value: model.report?.natType)
        .navigationTitle("CGNAT / NAT")
        .toolTitleDisplayMode()
        .onAppear { if autostart { Task { await model.run() } } }
    }

    private func typeCard(_ report: NATReport) -> some View {
        let (color, symbol) = style(for: report.natType)
        return HStack(spacing: 14) {
            Image(systemName: symbol).font(.largeTitle).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(report.natType.rawValue)).font(.title3.weight(.bold))
                if !report.cgnatHops.isEmpty {
                    Text("CGNAT: \(report.cgnatHops.joined(separator: ", "))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(16).card()
    }

    private func addressCard(_ report: NATReport) -> some View {
        VStack(spacing: 0) {
            InfoRow(label: "Локальный адрес", value: report.localIP ?? "—", mono: true)
            Divider().padding(.leading, 14)
            InfoRow(label: "Внешний адрес", value: report.publicIP ?? "—", mono: true)
            if !report.privateHops.isEmpty {
                Divider().padding(.leading, 14)
                InfoRow(label: "Приватные хопы", value: report.privateHops.joined(separator: "\n"), mono: true)
            }
        }
        .card()
    }

    private func findingsCard(_ report: NATReport) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(report.findings.enumerated()), id: \.offset) { idx, finding in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "info.circle").font(.caption).foregroundStyle(.blue).padding(.top, 2)
                    Text(LocalizedStringKey(finding)).font(.callout)
                    Spacer()
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                if idx < report.findings.count - 1 { Divider().padding(.leading, 40) }
            }
        }
        .card()
    }

    private func style(for type: NATReport.NATType) -> (Color, String) {
        switch type {
        case .none: return (.green, "checkmark.circle.fill")
        case .singleNAT: return (.blue, "arrow.triangle.branch")
        case .doubleNAT: return (.orange, "arrow.triangle.branch")
        case .cgnat: return (.red, "exclamationmark.triangle.fill")
        case .unknown: return (.gray, "questionmark.circle")
        }
    }
}
