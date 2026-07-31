import SwiftUI
import NetworkKit

/// Central list of all scheduled tasks.
struct ScheduledTasksView: View {
    @Environment(ScheduledTaskStore.self) private var store
    @Environment(TaskScheduler.self) private var scheduler
    @State private var showHistory = false

    var body: some View {
        Form {
            Section {
                if store.tasks.isEmpty {
                    Text("No tasks. Add a schedule from a test’s card.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.tasks) { task in
                        taskRow(task)
                    }
                    .onDelete { offsets in
                        for i in offsets { store.remove(store.tasks[i]) }
                    }
                }
            } header: {
                Text("Tasks")
            } footer: {
                Text("These run only while the app is open: iOS doesn’t launch apps on a timer in the background. For background runs, set up an automation in Shortcuts.")
            }

            Section {
                Button {
                    showHistory = true
                } label: {
                    Label("Scheduled run history", systemImage: "clock.arrow.circlepath")
                }
            } footer: {
                Text("A separate history of results from scheduled runs.")
            }
        }
        .navigationTitle("Schedule")
        #if os(iOS)
        .toolbarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: $showHistory) {
            HistoryView(source: .scheduled, title: "Scheduled run history")
                .presentationDetents([.large])
        }
    }

    private func taskRow(_ task: ScheduledTask) -> some View {
        HStack {
            Image(systemName: task.isEnabled ? "clock.badge.checkmark" : "clock.badge.xmark")
                .foregroundStyle(task.isEnabled ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title).font(.callout)
                Text("every \(intervalLabel(task.intervalMinutes))"
                     + (task.lastSummary.map { " · \($0)" } ?? ""))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Toggle("Run on a schedule", isOn: Binding(
                get: { task.isEnabled },
                set: { var t = task; t.isEnabled = $0; store.update(t) }
            ))
            .labelsHidden()
        }
    }

    private func intervalLabel(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes) min" : "\(minutes / 60) h"
    }
}

/// A reusable "Schedule" section for a test card. Independent of webhooks — it
/// just schedules the test to run and record to the scheduled history.
struct SchedulingSection: View {
    /// Builds the task kind from the card's current target.
    let makeKind: () -> ScheduledTask.Kind?
    /// A stable identity for the current target, to find an existing task.
    let matches: (ScheduledTask) -> Bool

    @Environment(ScheduledTaskStore.self) private var store
    @State private var interval = 30

    private let intervals = [5, 15, 30, 60, 180, 360]

    private var existing: ScheduledTask? { store.tasks.first(where: matches) }

    var body: some View {
        Section {
            if let existing {
                Toggle("Auto-run enabled", isOn: Binding(
                    get: { existing.isEnabled },
                    set: { var t = existing; t.isEnabled = $0; store.update(t) }
                ))
                Picker("Interval", selection: Binding(
                    get: { existing.intervalMinutes },
                    set: { var t = existing; t.intervalMinutes = $0; store.update(t) }
                )) {
                    ForEach(intervals, id: \.self) { Text(label($0)).tag($0) }
                }
                if let summary = existing.lastSummary, let last = existing.lastRun {
                    Text("Last: \(last.formatted(date: .omitted, time: .shortened)) — \(summary)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button("Remove from schedule", role: .destructive) {
                    store.remove(existing)
                }
            } else {
                Picker("Interval", selection: $interval) {
                    ForEach(intervals, id: \.self) { Text(label($0)).tag($0) }
                }
                Button {
                    if let kind = makeKind() {
                        store.add(ScheduledTask(kind: kind, intervalMinutes: interval))
                    }
                } label: {
                    Label("Run on a schedule", systemImage: "clock.arrow.2.circlepath")
                }
                .disabled(makeKind() == nil)
            }
        } header: {
            Text("Schedule")
        } footer: {
            Text("The test runs on its own while the app is open and lands in the scheduled run history. Independent of webhooks.")
        }
    }

    private func label(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes) min" : "\(minutes / 60) h"
    }
}
