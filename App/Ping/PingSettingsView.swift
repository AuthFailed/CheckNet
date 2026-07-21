import SwiftUI

struct PingSettingsView: View {
    @Bindable var model: PingViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Тип пакета") {
                    Picker("Тип", selection: $model.probeType) {
                        ForEach(ProbeType.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    if model.probeType == .tcp {
                        Stepper(value: $model.tcpPort, in: 1...65535) {
                            LabeledContent("Порт") { Text("\(model.tcpPort)").monospaced() }
                        }
                    }
                }

                Section("Параметры") {
                    if model.probeType == .icmp {
                        Stepper(value: $model.packetSize, in: 0...1472, step: 8) {
                            LabeledContent("Размер пакета") {
                                Text("\(model.packetSize) байт").monospaced().foregroundStyle(.secondary)
                            }
                        }
                    }
                    Toggle("Непрерывно", isOn: $model.continuous)
                    if !model.continuous {
                        Stepper(value: $model.count, in: 1...1000) {
                            LabeledContent("Количество") { Text("\(model.count)").monospaced() }
                        }
                    }
                    stepperDouble("Интервал", value: $model.interval, range: 0.2...10, step: 0.1, unit: "с")
                    stepperDouble("Таймаут", value: $model.timeout, range: 0.5...15, step: 0.5, unit: "с")
                    if model.probeType == .icmp {
                        Stepper(value: $model.ttl, in: 1...255) {
                            LabeledContent("TTL") { Text("\(model.ttl)").monospaced() }
                        }
                    }
                }

                if model.probeType == .icmp {
                    Section {
                        Toggle("Не фрагментировать (DF)", isOn: $model.dontFragment)
                        Toggle("Обратный DNS (rDNS)", isOn: $model.reverseDNS)
                    }
                }

                Section {
                    Button("Сбросить по умолчанию", role: .destructive) {
                        model.resetToDefaults()
                    }
                }
            }
            .navigationTitle("Настройки Ping")
            #if os(iOS)
            .toolbarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func stepperDouble(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, unit: String) -> some View {
        Stepper(value: value, in: range, step: step) {
            LabeledContent(title) {
                Text(String(format: "%.1f %@", value.wrappedValue, unit)).monospaced().foregroundStyle(.secondary)
            }
        }
    }
}
