import SwiftUI
import NetworkKit

/// Configure the recurring, foreground webhook schedule.
struct WebhookScheduleView: View {
    @Environment(WebhookScheduler.self) private var scheduler
    @State private var draft = WebhookSchedule()
    @State private var loaded = false

    private let intervals = [5, 15, 30, 60, 180, 360]

    var body: some View {
        Form {
            Section {
                Toggle("Периодический запуск", isOn: $draft.isEnabled)
                Picker("Интервал", selection: $draft.intervalMinutes) {
                    ForEach(intervals, id: \.self) { minutes in
                        Text(intervalLabel(minutes)).tag(minutes)
                    }
                }
            } footer: {
                Text("Работает, пока приложение открыто: iOS не запускает приложение по таймеру в фоне. Для запуска в фоне настройте автоматизацию в приложении «Команды» с нужным временем и действием «Проверить блокировку».")
            }

            Section("Проверки") {
                ForEach(BlockingCheck.allCases) { check in
                    Button {
                        toggle(check)
                    } label: {
                        HStack {
                            Image(systemName: draft.checkIDs.contains(check.rawValue) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(draft.checkIDs.contains(check.rawValue) ? Color.accentColor : .secondary)
                            Text(LocalizedStringKey(check.title))
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Section("Цель (необязательно)") {
                TextField("Домен по умолчанию у каждой проверки", text: $draft.target)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
            }

            if let last = scheduler.lastRun {
                Section("Последний запуск") {
                    Text(last.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption).foregroundStyle(.secondary)
                    if let summary = scheduler.lastSummary {
                        Text(summary).font(.caption)
                    }
                }
            }
        }
        .navigationTitle("Расписание")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            guard !loaded else { return }
            draft = scheduler.schedule
            loaded = true
        }
        .onDisappear { scheduler.update(draft) }
    }

    private func toggle(_ check: BlockingCheck) {
        if let index = draft.checkIDs.firstIndex(of: check.rawValue) {
            draft.checkIDs.remove(at: index)
        } else {
            draft.checkIDs.append(check.rawValue)
        }
    }

    private func intervalLabel(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) мин" }
        let hours = minutes / 60
        return "\(hours) ч"
    }
}
