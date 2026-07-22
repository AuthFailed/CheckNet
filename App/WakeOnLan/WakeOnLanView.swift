import SwiftUI
import NetworkKit

struct WakeOnLanView: View {
    @State private var mac = ""
    @State private var broadcast = "255.255.255.255"
    @State private var port = 9
    @State private var status: Status?

    enum Status: Equatable {
        case sent, failed(String)
    }

    private var macValid: Bool { WakeOnLan.parseMAC(mac) != nil }

    var body: some View {
        ToolScaffold {
            VStack(spacing: 0) {
                fieldRow(icon: "number", title: "MAC-адрес") {
                    TextField("AA:BB:CC:DD:EE:FF", text: $mac)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.characters)
                        #endif
                }
                Divider().padding(.leading, 44)
                fieldRow(icon: "dot.radiowaves.right", title: "Broadcast") {
                    TextField("255.255.255.255", text: $broadcast)
                        .font(.system(.body, design: .monospaced))
                        #if os(iOS)
                        .keyboardType(.numbersAndPunctuation)
                        #endif
                }
                Divider().padding(.leading, 44)
                fieldRow(icon: "poweroutlet.type.b", title: "Порт") {
                    Stepper(value: $port, in: 1...65535) {
                        Text("\(port)").monospacedDigit()
                    }
                }
            }
            .card()

            if let status {
                switch status {
                case .sent:
                    banner(icon: "checkmark.circle.fill", color: .green,
                           text: "Магический пакет отправлен на \(mac.uppercased())")
                case .failed(let msg):
                    banner(icon: "exclamationmark.triangle.fill", color: .orange, text: msg)
                }
            }
        } content: {
            Text("Wake-on-LAN работает только в локальной сети и требует, чтобы устройство поддерживало пробуждение по сети.")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
        } bottom: {
            Button {
                send()
            } label: {
                Label("Разбудить", systemImage: "power")
                    .font(.headline).frame(maxWidth: .infinity).frame(minHeight: 52)
                    .foregroundStyle(.white)
                    .background(macValid ? AnyShapeStyle(Color.blue) : AnyShapeStyle(Color.gray.opacity(0.4)),
                                in: RoundedRectangle(cornerRadius: 15))
            }
            .disabled(!macValid)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(.bar)
        }
        .navigationTitle("Wake-on-LAN")
        .toolTitleDisplayMode()
    }

    private func send() {
        do {
            try WakeOnLan.wake(mac: mac, broadcast: broadcast, port: UInt16(port))
            withAnimation { status = .sent }
        } catch {
            withAnimation { status = .failed(error.localizedDescription) }
        }
    }

    private func fieldRow<Content: View>(icon: String, title: String, @ViewBuilder content: () -> Content) -> some View {
        // No fixed 92 pt label column: German and Turkish labels are longer than
        // the Russian ones and were truncated. At accessibility sizes label and
        // value cannot share a line at all, so the row stacks instead.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                Image(systemName: icon).foregroundStyle(.secondary).frame(minWidth: 20)
                Text(LocalizedStringKey(title)).foregroundStyle(.secondary)
                content()
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 6) {
                Label {
                    Text(LocalizedStringKey(title)).foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: icon).foregroundStyle(.secondary)
                }
                content()
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
    }

    private func banner(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(color)
            Text(LocalizedStringKey(text)).font(.callout)
            Spacer()
        }
        .padding(14).card()
    }
}
