import SwiftUI

/// The "Блокировки" tab — checks that reveal local ISP restrictions the user's
/// own connection is subject to (transparency/diagnostics).
struct BlockingView: View {
    @State private var path: [BlockingRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    ForEach(BlockingCheck.allCases) { check in
                        Button {
                            path.append(BlockingRoute(check: check))
                        } label: {
                            row(check)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Проверки ограничений")
                } footer: {
                    Text("Каждая проверка сравнивает ваше соединение с эталоном и показывает, какие локальные ограничения применяет ваш провайдер. Только диагностика.")
                }
            }
            .navigationTitle("Блокировки")
            .navigationDestination(for: BlockingRoute.self) { route in
                BlockingCheckView(check: route.check)
            }
        }
    }

    private func row(_ check: BlockingCheck) -> some View {
        HStack(spacing: 13) {
            Image(systemName: check.systemImage)
                .font(.system(size: 17))
                .foregroundStyle(.tint)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(check.title).foregroundStyle(.primary)
                Text(check.subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

struct BlockingRoute: Hashable {
    let check: BlockingCheck
}
