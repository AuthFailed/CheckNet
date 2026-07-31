import SwiftUI

struct PingSettingsView: View {
    @Bindable var model: PingViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Packet type") {
                    Picker("Type", selection: $model.probeType) {
                        ForEach(ProbeType.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    if model.probeType == .tcp {
                        Stepper(value: $model.tcpPort, in: 1...65535) {
                            LabeledContent("Port") { Text("\(model.tcpPort)").monospaced() }
                        }
                    }
                }

                Section("Parameters") {
                    if model.probeType == .icmp {
                        Stepper(value: $model.packetSize, in: 0...1472, step: 8) {
                            LabeledContent("Packet size") {
                                Text("\(model.packetSize) bytes").monospaced().foregroundStyle(.secondary)
                            }
                        }
                    }
                    Toggle("Continuous", isOn: $model.continuous)
                    if !model.continuous {
                        Stepper(value: $model.count, in: 1...1000) {
                            LabeledContent("Count") { Text("\(model.count)").monospaced() }
                        }
                    }
                    stepperDouble("Interval", value: $model.interval, range: 0.2...10, step: 0.1, unit: "s")
                    stepperDouble("Timeout", value: $model.timeout, range: 0.5...15, step: 0.5, unit: "s")
                    if model.probeType == .icmp {
                        Stepper(value: $model.ttl, in: 1...255) {
                            LabeledContent("TTL") { Text("\(model.ttl)").monospaced() }
                        }
                    }
                }

                if model.probeType == .icmp {
                    Section {
                        Toggle("Don't fragment (DF)", isOn: $model.dontFragment)
                        Toggle("Reverse DNS (rDNS)", isOn: $model.reverseDNS)
                    }
                }

                Section {
                    Button("Reset to defaults", role: .destructive) {
                        model.resetToDefaults()
                    }
                }
            }
            .navigationTitle("Ping settings")
            #if os(iOS)
            .toolbarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
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
