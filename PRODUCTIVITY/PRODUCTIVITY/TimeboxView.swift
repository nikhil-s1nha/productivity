import SwiftUI

struct TimeboxView: View {
    @EnvironmentObject private var store: TaskStore
    @State private var selectedDate: Date = .now
    @State private var editingTask: TaskItem? = nil
    @State private var showUnplannedSheet = false

    @AppStorage("wakeHour") private var wakeHour: Int = 7
    @AppStorage("wakeMinute") private var wakeMinute: Int = 0
    @AppStorage("sleepHour") private var sleepHour: Int = 23
    @AppStorage("sleepMinute") private var sleepMinute: Int = 30
    @State private var showSettings = false
    @State private var completedAnchors: Set<String> = []
    private func anchorKey(_ title: String, date: Date) -> String {
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let y = comps.year ?? 0, m = comps.month ?? 0, d = comps.day ?? 0
        return "\(y)-\(m)-\(d)-\(title)"
    }

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
                        ForEach(Array(fullDayPlan.enumerated()), id: \.offset) { idx, itm in
                            TimelineRow(
                                item: itm,
                                isFirst: idx == 0,
                                isLast: idx == fullDayPlan.count - 1,
                                approachingMinutes: approachingMinutes(for: itm)
                            ) { tapped in
                                if tapped.title == "Wake up!" || tapped.title == "Sleep Well!" {
                                    let key = anchorKey(tapped.title, date: selectedDate)
                                    if completedAnchors.contains(key) { completedAnchors.remove(key) } else { completedAnchors.insert(key) }
                                } else {
                                    var copy = tapped
                                    copy.isCompleted.toggle()
                                    store.update(copy)
                                }
                            }
                            .onTapGesture { editingTask = itm }
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
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Timebox").font(.largeTitle).bold()
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
            }
            .sheet(item: $editingTask) { t in
                TimeboxEditor(task: t, selectedDate: $selectedDate)
                    .environmentObject(store)
            }
            .sheet(isPresented: $showUnplannedSheet) {
                UnplannedPickerSheet(selectedDate: $selectedDate)
                    .environmentObject(store)
            }
            .sheet(isPresented: $showSettings) {
                TimeboxSettingsSheet(wakeHour: $wakeHour, wakeMinute: $wakeMinute,
                                     sleepHour: $sleepHour, sleepMinute: $sleepMinute)
            }
            .overlay(alignment: .bottomTrailing) {
                Button { showUnplannedSheet = true } label: {
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

    private var anchorTasks: [TaskItem] {
        let cal = Calendar.current
        func at(_ hour: Int, _ minute: Int) -> Date {
            cal.date(bySettingHour: hour, minute: minute, second: 0, of: selectedDate) ?? selectedDate
        }
        let wakeDate = at(wakeHour, wakeMinute)
        let sleepDate = at(sleepHour, sleepMinute)
        let wakeCompleted = completedAnchors.contains(anchorKey("Wake up!", date: selectedDate))
        let sleepCompleted = completedAnchors.contains(anchorKey("Sleep Well!", date: selectedDate))
        let wake = TaskItem(id: UUID(), title: "Wake up!", note: "", createdAt: .now,
                            dueDate: nil, scheduledStart: wakeDate,
                            durationMinutes: 0, isCompleted: wakeCompleted, tags: [])
        let sleep = TaskItem(id: UUID(), title: "Sleep Well!", note: "", createdAt: .now,
                             dueDate: nil, scheduledStart: sleepDate,
                             durationMinutes: 0, isCompleted: sleepCompleted, tags: [])
        return [wake, sleep]
    }
    private var fullDayPlan: [TaskItem] {
        (dayPlan + anchorTasks).sorted { ($0.scheduledStart ?? .distantPast) < ($1.scheduledStart ?? .distantPast) }
    }

    private func approachingMinutes(for item: TaskItem) -> Int? {
        guard let start = item.scheduledStart, start > .now else { return nil }
        let minutes = Int((start.timeIntervalSinceNow / 60.0).rounded())
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
    let onToggle: ((TaskItem) -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Timeline rail with icon
            VStack(spacing: 0) {
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
                Rectangle()
                    .fill(styleColor.opacity(isLast ? 0 : 0.35))
                    .frame(width: 2, height: isLast ? 8 : 24)
            }
            .frame(width: 48)

            // Content
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    if let start = item.scheduledStart {
                        if let dur = item.durationMinutes, dur > 0,
                           let end = Calendar.current.date(byAdding: .minute, value: dur, to: start) {
                            let range = start.formatted(date: .omitted, time: .shortened) + " – " + end.formatted(date: .omitted, time: .shortened)
                            Text("\(range) (\(formatDuration(minutes: dur)))")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.secondary)
                        } else {
                            Text(start.formatted(date: .omitted, time: .shortened))
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
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
            Button {
                if let onToggle { onToggle(item) }
                else {
                    var copy = item
                    copy.isCompleted.toggle()
                    store.update(copy)
                }
            } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.isCompleted ? Color.blue : Color.red)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
        .contentShape(Rectangle())
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                if let onToggle { onToggle(item) }
                else {
                    var copy = item
                    copy.isCompleted.toggle()
                    store.update(copy)
                }
            } label: {
                Label(item.isCompleted ? "Uncomplete" : "Complete",
                      systemImage: item.isCompleted ? "arrow.uturn.backward" : "checkmark")
            }
            .tint(item.isCompleted ? .gray : .green)
        }
    }

    // prefer tagged color if present
    private var taggedColor: Color? {
        if let hex = item.tags.first(where: { $0.hasPrefix("color:") })?
            .replacingOccurrences(of: "color:", with: "") {
            return Color(hex: hex)
        }
        return nil
    }

    private var styleColor: Color {
        if let c = taggedColor { return c }
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

    private var taggedSymbol: String? {
        item.tags.first(where: { $0.hasPrefix("icon:") })?.replacingOccurrences(of: "icon:", with: "")
    }

    private var leadingSymbol: String {
        if let tagged = taggedSymbol { return tagged }
        if item.title == "Wake up!" { return "alarm.fill" }
        if item.title == "Sleep Well!" { return "moon.stars.fill" }
        guard let start = item.scheduledStart else { return "circle.fill" }
        let hour = Calendar.current.component(.hour, from: start)
        if hour < 8 { return "moon.fill" }
        if hour < 12 { return "alarm.fill" }
        if hour < 18 { return "sun.max.fill" }
        return "moon.stars.fill"
    }

    private func formatDuration(minutes: Int) -> String {
        let h = minutes / 60
        let m = minutes % 60
        if h > 0 && m > 0 { return "\(h) hr, \(m) min" }
        if h > 0 { return "\(h) hr" }
        return "\(m) min"
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
    @AppStorage("wakeHour") private var wakeHour: Int = 7
    @AppStorage("wakeMinute") private var wakeMinute: Int = 0
    @AppStorage("sleepHour") private var sleepHour: Int = 23
    @AppStorage("sleepMinute") private var sleepMinute: Int = 30
    @State private var iconName: String = ""
    @State private var showIconPicker: Bool = false
    @State private var colorHex: String = ""
    @State private var showColorPicker: Bool = false

    private var isAnchor: Bool { task.title == "Wake up!" || task.title == "Sleep Well!" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Controls (compact card, no internal scrolling)
            VStack(alignment: .leading, spacing: 12) {
                Text(task.title)
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 2)

                if isAnchor {
                    DatePicker("Time", selection: $start, displayedComponents: [.hourAndMinute])
                        .datePickerStyle(.compact)
                } else {
                    // Start row
                    HStack {
                        Text("Start")
                        Spacer()
                        DatePicker("Start", selection: $start, displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()
                            .datePickerStyle(.compact)
                    }
                    // Duration row
                    HStack {
                        Text("Duration: \(duration)m")
                        Spacer()
                        Stepper(value: $duration, in: 5...240, step: 5) { EmptyView() }
                            .labelsHidden()
                    }
                    // Icon + Color row directly under duration
                    HStack(spacing: 12) {
                        Button { showColorPicker = true } label: {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(
                                    Color(hex: colorHex)
                                    ?? (task.tags.first(where: { $0.hasPrefix("color:") })
                                            .flatMap { Color(hex: $0.replacingOccurrences(of: "color:", with: "")) }
                                        ?? Color.gray)
                                )
                                .frame(width: 28, height: 28)
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.3), lineWidth: 1))
                        }
                        .buttonStyle(.plain)

                        Image(systemName: iconName.isEmpty ? "square.dashed" : iconName)
                            .font(.title3)
                            .frame(width: 28, height: 28)
                            .padding(6)
                            .background(Circle().fill(Color.secondary.opacity(0.12)))

                        Text(iconName.isEmpty ? "No icon" : "Icon selected")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Edit") { showIconPicker = true }
                    }
                    .padding(.top, 2)
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(.systemBackground)))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.06)))
            .padding(.horizontal, 8)

            // Preview (prominent & scrollable)
            Text("Preview").font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(previewPlan.enumerated()), id: \.offset) { idx, itm in
                        TimelineRow(
                            item: itm,
                            isFirst: idx == 0,
                            isLast: idx == previewPlan.count - 1,
                            approachingMinutes: nil,
                            onToggle: nil
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .frame(maxHeight: .infinity)
            .overlay(Divider().opacity(0.08), alignment: .top)

            if !isAnchor {
                Button {
                    task.scheduledStart = start
                    task.durationMinutes = duration
                    var tags = task.tags.filter { !$0.hasPrefix("icon:") && !$0.hasPrefix("color:") }
                    if !iconName.isEmpty { tags.append("icon:\(iconName)") }
                    if !colorHex.isEmpty { tags.append("color:\(colorHex)") }
                    task.tags = tags
                    store.update(task)
                    dismiss()
                } label: {
                    Label("Schedule", systemImage: "calendar.badge.plus").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
        .sheet(isPresented: $showIconPicker) { IconPickerSheet(iconName: $iconName) }
        .sheet(isPresented: $showColorPicker) { ColorPickerSheet(colorHex: $colorHex) }
        .onAppear {
            if let existing = task.scheduledStart { start = existing }
            else {
                start = Calendar.current.date(
                    bySettingHour: Calendar.current.component(.hour, from: .now),
                    minute: 0, second: 0, of: selectedDate) ?? selectedDate
            }
            duration = task.durationMinutes ?? (isAnchor ? 0 : 30)
            if let tag = task.tags.first(where: { $0.hasPrefix("icon:") }) {
                iconName = tag.replacingOccurrences(of: "icon:", with: "")
            }
            if let tag = task.tags.first(where: { $0.hasPrefix("color:") }) {
                colorHex = tag.replacingOccurrences(of: "color:", with: "")
            }
        }
        .onChange(of: start) { _ in
            if isAnchor {
                task.scheduledStart = start
                task.durationMinutes = 0
                store.update(task)
            }
        }
        .navigationTitle("Timebox")
    }

    private var anchorTasksForSelectedDate: [TaskItem] {
        let cal = Calendar.current
        func at(_ hour: Int, _ minute: Int) -> Date {
            cal.date(bySettingHour: hour, minute: minute, second: 0, of: selectedDate) ?? selectedDate
        }
        let wake = TaskItem(id: UUID(), title: "Wake up!", note: "", createdAt: .now,
                            dueDate: nil, scheduledStart: at(wakeHour, wakeMinute),
                            durationMinutes: 0, isCompleted: false, tags: [])
        let sleep = TaskItem(id: UUID(), title: "Sleep Well!", note: "", createdAt: .now,
                             dueDate: nil, scheduledStart: at(sleepHour, sleepMinute),
                             durationMinutes: 0, isCompleted: false, tags: [])
        return [wake, sleep]
    }

    private var previewPlan: [TaskItem] {
        let cal = Calendar.current
        var items = store.tasks.filter { t in
            guard let s = t.scheduledStart else { return false }
            return cal.isDate(s, inSameDayAs: selectedDate) && t.id != task.id
        }
        let anchors = anchorTasksForSelectedDate.filter { a in a.title != task.title }
        items.append(contentsOf: anchors)

        var temp = task
        temp.scheduledStart = start
        temp.durationMinutes = (task.title == "Wake up!" || task.title == "Sleep Well!") ? 0 : duration
        var tags = temp.tags.filter { !$0.hasPrefix("icon:") && !$0.hasPrefix("color:") }
        if !iconName.isEmpty { tags.append("icon:\(iconName)") }
        if !colorHex.isEmpty { tags.append("color:\(colorHex)") }
        temp.tags = tags
        items.append(temp)

        return items.sorted { ($0.scheduledStart ?? .distantPast) < ($1.scheduledStart ?? .distantPast) }
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

    private enum Bucket: String, CaseIterable {
        case overdue = "Overdue", today = "Today", tomorrow = "Tomorrow",
             week = "This Week", later = "Later", none = "No Due Date"
    }
    private var grouped: [(Bucket, [TaskItem])] {
        let cal = Calendar.current
        let startToday = cal.startOfDay(for: .now)
        let startTomorrow = cal.date(byAdding: .day, value: 1, to: startToday)!
        let startDayAfter = cal.date(byAdding: .day, value: 2, to: startToday)!
        let startNextWeek = cal.date(byAdding: .day, value: 7, to: startToday)!
        func bucket(for t: TaskItem) -> Bucket {
            guard let d = t.dueDate else { return .none }
            if d < startToday { return .overdue }
            if cal.isDate(d, inSameDayAs: startToday) { return .today }
            if cal.isDate(d, inSameDayAs: startTomorrow) { return .tomorrow }
            if d < startNextWeek { return .week }
            return .later
        }
        let dict = Dictionary(grouping: sourceTasks, by: bucket(for:))
        let order: [Bucket] = [.overdue, .today, .tomorrow, .week, .later, .none]
        return order.compactMap { b in
            guard let items = dict[b] else { return nil }
            let sorted = items.sorted {
                let l = $0.dueDate ?? .distantFuture
                let r = $1.dueDate ?? .distantFuture
                if l != r { return l < r }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
            return (b, sorted)
        }
    }

    var body: some View {
        NavigationStack {
            if sourceTasks.isEmpty {
                Text("No unplanned tasks").foregroundStyle(.secondary)
                    .navigationTitle("")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .principal) { Text("Add to Timebox").font(.title2).bold() }
                        ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                    }
            } else {
                List {
                    ForEach(grouped, id: \.0) { bucket, items in
                        Section(bucket.rawValue) {
                            ForEach(items) { t in
                                NavigationLink {
                                    TimeboxEditor(task: t, selectedDate: $selectedDate)
                                        .environmentObject(store)
                                } label: {
                                    HStack {
                                        Text(t.title)
                                        Spacer()
                                        if let d = t.dueDate {
                                            Text(d.formatted(.dateTime.month().day()))
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                        if let dur = t.durationMinutes {
                                            Text("\(dur)m").font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) { Text("Add to Timebox").font(.title2).bold() }
                    ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                }
            }
        }
    }
}

private struct TimeboxSettingsSheet: View {
    @Binding var wakeHour: Int
    @Binding var wakeMinute: Int
    @Binding var sleepHour: Int
    @Binding var sleepMinute: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Wake Up") { TimePickerView(hour: $wakeHour, minute: $wakeMinute) }
                Section("Sleep") { TimePickerView(hour: $sleepHour, minute: $sleepMinute) }
            }
            .navigationTitle("Defaults")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

private struct TimePickerView: View {
    @Binding var hour: Int
    @Binding var minute: Int
    var body: some View {
        HStack {
            Picker("Hour", selection: $hour) { ForEach(0..<24, id: \.self) { Text(String(format: "%02d", $0)).tag($0) } }
                .pickerStyle(.wheel)
            Picker("Minute", selection: $minute) {
                ForEach([0,5,10,15,20,25,30,35,40,45,50,55], id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
            }.pickerStyle(.wheel)
        }
        .frame(height: 120)
    }
}

// MARK: - Color Hex Helpers
extension Color {
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = Int(s, radix: 16) else { return nil }
        let r = Double((v >> 16) & 0xFF) / 255.0
        let g = Double((v >> 8) & 0xFF) / 255.0   // <- fixed
        let b = Double(v & 0xFF) / 255.0
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: 1.0)
    }
}

#if canImport(UIKit)
import UIKit
private func hexString(from color: Color) -> String? {
    // UIColor(color) is available from iOS 14+
    let ui = UIColor(color)
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    guard ui.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
    return String(format: "%02X%02X%02X", Int(r*255), Int(g*255), Int(b*255))
}
#else
private func hexString(from color: Color) -> String? { nil }
#endif

// MARK: - Color Picker Sheet
private struct ColorPickerSheet: View {
    @Binding var colorHex: String
    @Environment(\.dismiss) private var dismiss
    @State private var color: Color = .accentColor
    private let presets: [Color] = [.blue, .teal, .green, .mint, .yellow, .orange, .pink, .purple, .indigo, .red, .brown, .gray]

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 6), spacing: 12) {
                    ForEach(Array(presets.enumerated()), id: \.offset) { _, c in
                        Button {
                            color = c
                            if let h = hexString(from: c) { colorHex = h }
                        } label: {
                            Circle().fill(c).frame(width: 36, height: 36)
                        }
                    }
                    Button { colorHex = "" } label: {
                        ZStack {
                            Circle().strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [4]))
                            Image(systemName: "slash.circle.fill").font(.title3).opacity(0.4)
                        }.frame(width: 36, height: 36)
                    }
                }
                .padding(.horizontal, 16)

                ColorPicker("Custom", selection: $color, supportsOpacity: false)
                    .padding(.horizontal, 16)
                    .onChange(of: color) { newValue in
                        if let h = hexString(from: newValue) { colorHex = h }
                    }

                Spacer()
            }
            .navigationTitle("Choose Color")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear { if let c = Color(hex: colorHex) { color = c } }
        }
    }
}

// MARK: - Icon Picker Sheet
private struct IconPickerSheet: View {
    @Binding var iconName: String
    @Environment(\.dismiss) private var dismiss
    private let options = [
        "briefcase.fill", "graduationcap.fill", "book.fill", "pencil", "laptopcomputer",
        "dumbbell", "basketball.fill", "bicycle", "bolt.fill", "leaf.fill",
        "gamecontroller.fill", "music.note", "camera.fill", "doc.text.fill", "figure.walk"
    ]
    var body: some View {
        NavigationStack {
            ScrollView {
                let cols = Array(repeating: GridItem(.flexible(), spacing: 12), count: 5)
                LazyVGrid(columns: cols, spacing: 12) {
                    Button { iconName = "" } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "slash.circle").font(.title2).frame(width: 40, height: 40)
                            Text("None").font(.caption2)
                        }
                        .frame(maxWidth: .infinity).padding(8)
                        .background(RoundedRectangle(cornerRadius: 10).stroke(iconName.isEmpty ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: iconName.isEmpty ? 2 : 1))
                    }.buttonStyle(.plain)
                    ForEach(options, id: \.self) { sym in
                        Button { iconName = sym } label: {
                            VStack(spacing: 6) {
                                Image(systemName: sym).font(.title2).frame(width: 40, height: 40)
                                Text(sym.replacingOccurrences(of: ".fill", with: "").replacingOccurrences(of: ".", with: " "))
                                    .lineLimit(1).minimumScaleFactor(0.6)
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity).padding(8)
                            .background(RoundedRectangle(cornerRadius: 10).stroke(iconName == sym ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: iconName == sym ? 2 : 1))
                        }.buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .navigationTitle("Choose Icon")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
