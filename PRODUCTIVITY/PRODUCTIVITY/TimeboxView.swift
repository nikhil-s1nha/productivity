import SwiftUI

struct TimeboxView: View {
    @EnvironmentObject private var store: TaskStore
    @State private var selectedDate: Date = .now
    @State private var showOnlyUnplanned = true

    var body: some View {
        NavigationStack {
            List {
                Section {
                    DatePicker("Day", selection: $selectedDate, displayedComponents: .date)
                    Toggle("Show only unplanned tasks", isOn: $showOnlyUnplanned)
                }

                Section("Tasks") {
                    ForEach(sourceTasks) { t in
                        NavigationLink {
                            TimeboxEditor(task: t, selectedDate: $selectedDate)
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(t.title).font(.body)
                                    if let d = t.durationMinutes { Text("\(d)m").font(.caption).foregroundStyle(.secondary) }
                                }
                                Spacer()
                                if let start = t.scheduledStart {
                                    Text(start, style: .time).foregroundStyle(.secondary)
                                } else {
                                    Image(systemName: "plus.square")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                }

                Section("Today’s Plan") {
                    ForEach(dayPlan) { t in
                        HStack {
                            Text(t.title)
                            Spacer()
                            if let start = t.scheduledStart, let dur = t.durationMinutes {
                                Text("\(start.formatted(date: .omitted, time: .shortened)) • \(dur)m")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Timebox")
        }
    }

    private var sourceTasks: [TaskItem] {
        store.tasks
            .filter { showOnlyUnplanned ? $0.scheduledStart == nil && !$0.isCompleted : !$0.isCompleted }
            .sorted { ($0.durationMinutes ?? 0) > ($1.durationMinutes ?? 0) }
    }

    private var dayPlan: [TaskItem] {
        store.tasks
            .filter {
                guard let start = $0.scheduledStart else { return false }
                return Calendar.current.isDate(start, inSameDayAs: selectedDate)
            }
            .sorted { ($0.scheduledStart ?? .distantPast) < ($1.scheduledStart ?? .distantPast) }
    }
}

private struct TimeboxEditor: View {
    @EnvironmentObject private var store: TaskStore
    @State var task: TaskItem
    @Binding var selectedDate: Date
    @State private var start: Date = .now
    @State private var duration: Int = 30

    var body: some View {
        Form {
            Text(task.title).font(.headline)

            DatePicker("Start", selection: $start, displayedComponents: [.date, .hourAndMinute])
            Stepper(value: $duration, in: 5...240, step: 5) {
                Text("Duration: \(duration)m")
            }

            Button {
                task.scheduledStart = start
                task.durationMinutes = duration
                store.update(task)
            } label: {
                Label("Schedule", systemImage: "calendar.badge.plus")
            }
            .buttonStyle(.borderedProminent)

            // Optional: push to EventKit Calendar
            // EventKitManager.shared.createCalendarEvent(for: task)
        }
        .onAppear {
            start = Calendar.current.date(
                bySettingHour: Calendar.current.component(.hour, from: .now),
                minute: 0, second: 0, of: selectedDate) ?? selectedDate
            duration = task.durationMinutes ?? 30
        }
        .navigationTitle("Timebox")
    }
}
