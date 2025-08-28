import SwiftUI

struct TimeboxView: View {
    @EnvironmentObject private var store: TaskStore
    @State private var selectedDate: Date = .now
    @State private var editingTask: TaskItem? = nil
    @State private var showUnplannedSheet = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                WeekStrip(selected: $selectedDate)

                Divider().opacity(0.15)

                ScrollView {
                    // Today's Plan timeline
                    Text("TODAY'S PLAN")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                    
                    VStack(alignment: .leading, spacing: 24) {
                        ForEach(dayPlanIndexed.indices, id: \.self) { i in
                            let element = dayPlanIndexed[i]
                            TimelineRow(
                                item: element.item,
                                isFirst: i == 0,
                                isLast: i == dayPlanIndexed.count - 1,
                                approachingMinutes: approachingMinutes(for: element.item)
                            )
                        }

                        if sourceTasks.isEmpty && dayPlan.isEmpty {
                            Text("No tasks for this day")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 40)
                        }
                    }
                    .padding(.vertical, 16)
                    .padding(.horizontal, 20)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Timebox")
            .sheet(item: $editingTask) { t in
                TimeboxEditor(task: t, selectedDate: $selectedDate)
                    .environmentObject(store)
            }
            .sheet(isPresented: $showUnplannedSheet) {
                UnplannedPickerSheet(selectedDate: $selectedDate)
                    .environmentObject(store)
            }
            .overlay(alignment: .bottomTrailing) {
                Button {
                    showUnplannedSheet = true
                } label: {
                    ZStack {
                        Circle().fill(Color.accentColor).frame(width: 56, height: 56)
                        Image(systemName: "plus").foregroundColor(.white).font(.system(size: 24, weight: .bold))
                    }
                }
                .padding(.trailing, 20).padding(.bottom, 28)
                .shadow(radius: 3, y: 2)
            }
        }
    }

    // MARK: Data slices

    private var sourceTasks: [TaskItem] {
        store.tasks
            .filter { $0.scheduledStart == nil && !$0.isCompleted }
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

    private var dayPlanIndexed: [(item: TaskItem, idx: Int)] {
        Array(dayPlan.enumerated()).map { ($0.element, $0.offset) }
    }

    private func approachingMinutes(for item: TaskItem) -> Int? {
        guard let start = item.scheduledStart, start > .now else { return nil }
        let minutes = Int((start.timeIntervalSinceNow / 60.0).rounded())
        // Treat "approaching" as within next 60 mins
        return minutes <= 60 ? minutes : nil
    }
}

// MARK: - Week strip

private struct WeekStrip: View {
    @Binding var selected: Date

    var body: some View {
        let cal = Calendar.current
        let start = cal.startOfWeek(for: selected)
        let days = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }

        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(days, id: \.self) { day in
                    VStack(spacing: 6) {
                        Text(day.formatted(.dateTime.weekday(.abbreviated)))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        ZStack {
                            Circle()
                                .fill(cal.isDate(day, inSameDayAs: selected) ? Color.accentColor : Color.clear)
                                .frame(width: 30, height: 30)
                            Text(day.formatted(.dateTime.day()))
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(cal.isDate(day, inSameDayAs: selected) ? .white : .primary)
                        }
                    }
                    .onTapGesture { selected = day }
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Color(.secondarySystemBackground))
    }
}

// MARK: - Timeline Row

private struct TimelineRow: View {
    @EnvironmentObject private var store: TaskStore

    let item: TaskItem
    let isFirst: Bool
    let isLast: Bool
    let approachingMinutes: Int?

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Timeline rail with icon
            VStack(spacing: 0) {
                // Top connector
                Rectangle()
                    .fill(styleColor.opacity(isFirst ? 0 : 0.35))
                    .frame(width: 2, height: isFirst ? 8 : 18)
                ZStack {
                    Circle()
                        .fill(styleColor.opacity(0.18))
                        .frame(width: 44, height: 44)
                    Image(systemName: leadingSymbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(styleColor)
                }
                // Bottom connector
                Rectangle()
                    .fill(styleColor.opacity(isLast ? 0 : 0.35))
                    .frame(width: 2, height: isLast ? 8 : 24)
            }
            .frame(width: 48)

            // Content
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    if let start = item.scheduledStart {
                        Text(start.formatted(date: .omitted, time: .shortened))
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.secondary)
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(item.title)
                    .font(.headline.weight(.semibold))
                    .strikethrough(item.isCompleted, color: .secondary)
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)

                if let mins = approachingMinutes, !item.isCompleted {
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                        Text("Use \(mins)m, task approaching.")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                }
            }
            Spacer()

            // Right status
            if item.isCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.blue)
            } else {
                Image(systemName: "circle")
                    .foregroundStyle(Color.red)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
        .contentShape(Rectangle())
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                var copy = item
                copy.isCompleted.toggle()
                store.update(copy)
            } label: {
                Label(item.isCompleted ? "Uncomplete" : "Complete",
                      systemImage: item.isCompleted ? "arrow.uturn.backward" : "checkmark")
            }
            .tint(item.isCompleted ? .gray : .green)
        }
    }

    private var styleColor: Color {
        // simple style color by hour of day
        guard let start = item.scheduledStart else { return .teal }
        let hour = Calendar.current.component(.hour, from: start)
        switch hour {
        case 0..<8: return .indigo
        case 8..<12: return .pink
        case 12..<18: return .orange
        default: return .blue
        }
    }

    private var leadingSymbol: String {
        guard let start = item.scheduledStart else { return "circle.fill" }
        let hour = Calendar.current.component(.hour, from: start)
        if hour < 8 { return "moon.fill" }
        if hour < 12 { return "alarm.fill" }
        if hour < 18 { return "sun.max.fill" }
        return "moon.stars.fill"
    }
}

// MARK: - Editor

private struct TimeboxEditor: View {
    @EnvironmentObject private var store: TaskStore
    @Environment(\.dismiss) private var dismiss
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
                dismiss()
            } label: {
                Label("Schedule", systemImage: "calendar.badge.plus")
            }
            .buttonStyle(.borderedProminent)
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

// MARK: - Helpers

fileprivate extension Calendar {
    func startOfWeek(for date: Date) -> Date {
        let comps = dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return self.date(from: comps) ?? date
    }
}

private struct UnplannedPickerSheet: View {
    @EnvironmentObject private var store: TaskStore
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedDate: Date

    private var sourceTasks: [TaskItem] {
        store.tasks.filter { $0.scheduledStart == nil && !$0.isCompleted }
            .sorted { ($0.durationMinutes ?? 0) > ($1.durationMinutes ?? 0) }
    }

    var body: some View {
        NavigationStack {
            if sourceTasks.isEmpty {
                Text("No unplanned tasks").foregroundStyle(.secondary)
                    .navigationTitle("Unplanned")
            } else {
                List {
                    ForEach(sourceTasks) { t in
                        NavigationLink {
                            TimeboxEditor(task: t, selectedDate: $selectedDate)
                                .environmentObject(store)
                        } label: {
                            HStack {
                                Text(t.title)
                                Spacer()
                                if let d = t.durationMinutes {
                                    Text("\(d)m").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .navigationTitle("Unplanned")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                }
            }
        }
    }
}
