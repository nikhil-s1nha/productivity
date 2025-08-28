import SwiftUI

private struct TaskSection: Identifiable {
    let id: String
    var items: [TaskItem]
}

struct ListsView: View {
    @EnvironmentObject var store: TaskStore
    @State private var showingNew = false
    @State private var showingSettings = false
    @State private var collapsedSections: Set<String> = []

    private enum DashboardSection { case today, upcoming, all, completed }
    @State private var selectedSection: DashboardSection? = nil

    var body: some View {
        NavigationStack {
            if let section = selectedSection {
                taskList(for: section)
            } else {
                dashboard
            }
        }
    }

    private var dashboard: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                dashboardBox(title: "Today", count: filteredItems(for: .today).count, color: .blue) { selectedSection = .today }
                dashboardBox(title: "Upcoming", count: filteredItems(for: .upcoming).count, color: .orange) { selectedSection = .upcoming }
            }
            HStack(spacing: 16) {
                dashboardBox(title: "All", count: store.tasks.count, color: .gray) { selectedSection = .all }
                dashboardBox(title: "Completed", count: filteredItems(for: .completed).count, color: .green) { selectedSection = .completed }
            }
            Spacer()
        }
        .padding()
        .navigationTitle("Lists")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showingNew = true } label: { Image(systemName: "plus.circle.fill") }
            }
            ToolbarItem(placement: .navigationBarLeading) {
                Button { showingSettings = true } label: { Image(systemName: "gearshape") }
            }
        }
        .sheet(isPresented: $showingNew) { NewTaskSheet { store.add($0) } }
        .sheet(isPresented: $showingSettings) { KeywordSettingsSheet().environmentObject(store) }
    }

    private func dashboardBox(title: String, count: Int, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 14).fill(color)
                Text("\(count)")
                    .font(.title3).bold().foregroundColor(.white)
                    .padding(12)
            }
            .overlay(
                VStack(alignment: .leading, spacing: 8) {
                    Text(title).font(.headline).foregroundColor(.white)
                }
                .padding(), alignment: .bottomLeading
            )
            .frame(maxWidth: .infinity, minHeight: 110)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func taskList(for section: DashboardSection) -> some View {
        List {
            ForEach(groupedSections(for: section)) { sec in
                let isCollapsed = collapsedSections.contains(sec.id)
                Section {
                    if !isCollapsed {
                        ForEach(sec.items) { item in
                            HStack(alignment: .top, spacing: 12) {
                                Button(action: { withAnimation { store.toggle(item.id) } }) {
                                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(item.isCompleted ? .green : .secondary)
                                        .frame(width: 28, height: 28)
                                        .contentShape(Circle())
                                }
                                .buttonStyle(.plain)
                                NavigationLink {
                                    TaskDetailView(task: item)
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.title)
                                            .font(.body.weight(.medium))
                                            .strikethrough(item.isCompleted, color: .secondary)
                                        if !item.note.isEmpty {
                                            Text(item.note).font(.subheadline).foregroundStyle(.secondary)
                                        }
                                        HStack(spacing: 8) {
                                            if let due = item.dueDate {
                                                let comps = Calendar.current.dateComponents([.hour, .minute, .second], from: due)
                                                let isMidnight = (comps.hour == 0 && comps.minute == 0 && comps.second == 0)
                                                Label {
                                                    Text(isMidnight ? due.formatted(.dateTime.month().day())
                                                                    : due.formatted(.dateTime.month().day().hour().minute()))
                                                        .font(.caption)
                                                } icon: { Image(systemName: "calendar") }
                                                .labelStyle(.titleAndIcon)
                                            }
                                            if let d = item.durationMinutes {
                                                Label("\(d)m", systemImage: "timer").font(.caption)
                                            }
                                        }
                                    }
                                    .contentShape(Rectangle())
                                }
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    withAnimation { store.toggle(item.id) }
                                } label: {
                                    Label(item.isCompleted ? "Uncomplete" : "Complete",
                                          systemImage: item.isCompleted ? "arrow.uturn.backward" : "checkmark.circle")
                                }
                                .tint(item.isCompleted ? .gray : .green)
                            }
                        }
                        .onDelete { offsets in
                            deleteFromStore(offsets, in: sec.items)
                        }
                    }
                } header: {
                    HStack {
                        Text(sec.id).font(.title3).bold()
                        Spacer()
                        Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if isCollapsed { collapsedSections.remove(sec.id) } else { collapsedSections.insert(sec.id) }
                    }
                }
            }
        }
        .navigationTitle(title(for: section))
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Back") { selectedSection = nil }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showingNew = true } label: { Image(systemName: "plus.circle.fill") }
            }
        }
        .sheet(isPresented: $showingNew) { NewTaskSheet { store.add($0) } }
    }

    private func title(for section: DashboardSection) -> String {
        switch section { case .today: return "Today"; case .upcoming: return "Upcoming"; case .all: return "All"; case .completed: return "Completed" }
    }

    private func filteredItems(for section: DashboardSection) -> [TaskItem] {
        let cal = Calendar.current
        let now = Date()
        switch section {
        case .today:
            return store.tasks.filter { ($0.scheduledStart ?? $0.dueDate).map(cal.isDateInToday) ?? false }
        case .upcoming:
            let end = cal.date(byAdding: .day, value: 3, to: now)!
            return store.tasks.filter {
                guard let d = ($0.scheduledStart ?? $0.dueDate) else { return false }
                return d > now && d < end && !$0.isCompleted
            }
        case .all:
            return store.tasks
        case .completed:
            let start = cal.date(byAdding: .day, value: -7, to: now)!
            return store.tasks.filter { $0.isCompleted && (($0.scheduledStart ?? $0.dueDate) ?? .distantPast) > start }
        }
    }

    private func groupedSections(for section: DashboardSection) -> [TaskSection] {
        let groups = Dictionary(grouping: filteredItems(for: section)) { (item: TaskItem) in
            item.tags.first ?? "Other"
        }
        return groups.keys.sorted().map { key in
            let items = (groups[key] ?? []).sorted {
                let lhs = $0.scheduledStart ?? $0.dueDate ?? $0.createdAt
                let rhs = $1.scheduledStart ?? $1.dueDate ?? $1.createdAt
                return lhs < rhs
            }
            return TaskSection(id: key, items: items)
        }
    }

    private func deleteFromStore(_ offsets: IndexSet, in sectionItems: [TaskItem]) {
        let ids = offsets.map { sectionItems[$0].id }
        let global = store.tasks.enumerated().compactMap { (idx, t) in ids.contains(t.id) ? idx : nil }
        store.delete(at: IndexSet(global))
    }
}

// Section wrapper (keeps compiler happy & isolates NavigationLink hit areas)
private struct SectionGroupView: View {
    let section: TaskSection
    let onToggle: (UUID) -> Void
    let onDelete: (IndexSet) -> Void

    var body: some View {
        Section(header: Text(section.id).font(.title3).bold()) {
            ForEach(section.items) { item in
                HStack(alignment: .top, spacing: 12) {
                    // Small isolated toggle button
                    Button(action: { onToggle(item.id) }) {
                        Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(item.isCompleted ? .green : .secondary)
                            .frame(width: 28, height: 28)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)

                    // Tapping the row navigates only
                    NavigationLink {
                        TaskDetailView(task: item)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title)
                                .font(.body.weight(.medium))
                                .strikethrough(item.isCompleted, color: .secondary)
                            if !item.note.isEmpty {
                                Text(item.note).font(.subheadline).foregroundStyle(.secondary)
                            }
                            HStack(spacing: 8) {
                                if let due = item.dueDate {
                                    let comps = Calendar.current.dateComponents([.hour, .minute, .second], from: due)
                                    let isMidnight = (comps.hour == 0 && comps.minute == 0 && comps.second == 0)
                                    Label {
                                        Text(isMidnight
                                             ? due.formatted(.dateTime.month().day())
                                             : due.formatted(.dateTime.month().day().hour().minute()))
                                            .font(.caption)
                                    } icon: {
                                        Image(systemName: "calendar")
                                    }
                                    .labelStyle(.titleAndIcon)
                                }
                                if let d = item.durationMinutes {
                                    Label("\(d)m", systemImage: "timer").font(.caption)
                                }
                            }
                        }
                        .contentShape(Rectangle())
                    }
                }
                // Swipe right to complete/uncomplete
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button { onToggle(item.id) } label: {
                        Label(item.isCompleted ? "Uncomplete" : "Complete",
                              systemImage: item.isCompleted ? "arrow.uturn.backward" : "checkmark.circle")
                    }
                    .tint(item.isCompleted ? .gray : .green)
                }
            }
            .onDelete(perform: onDelete)
        }
    }
}

// MARK: New Task sheet
private struct NewTaskSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var note = ""
    @State private var due: Date? = nil
    @State private var duration: Int = 0
    @State private var tags = ""

    var onSave: (TaskItem) -> Void

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title)
                TextField("Note", text: $note)
                Toggle("Due date", isOn: Binding(get: { due != nil }, set: { due = $0 ? .now : nil }))
                if let binding = Binding($due) {
                    DatePicker("Due", selection: binding, displayedComponents: [.date, .hourAndMinute])
                }
                Stepper(value: $duration, in: 0...600, step: 5) {
                    Text("Duration: \(duration)m (0 = unscheduled)")
                }
                TextField("Tags (comma separated)", text: $tags)
            }
            .navigationTitle("New Task")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let item = TaskItem(
                            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                            note: note,
                            dueDate: due,
                            durationMinutes: duration == 0 ? nil : duration,
                            tags: tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                        )
                        onSave(item)
                        dismiss()
                    }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

// MARK: Task details (autosave)
private struct TaskDetailView: View {
    @EnvironmentObject private var store: TaskStore
    @State var task: TaskItem

    @State private var saveWorkItem: DispatchWorkItem?
    private func scheduleAutoSave() {
        saveWorkItem?.cancel()
        let wi = DispatchWorkItem { store.update(task) }
        saveWorkItem = wi
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: wi)
    }

    var body: some View {
        Form {
            Section {
                TextField("Title", text: $task.title)
                TextField("Note", text: $task.note)
                Toggle("Completed", isOn: $task.isCompleted)
            }
            Section("Dates") {
                DatePicker("Due", selection: Binding(get: {
                    task.dueDate ?? .now
                }, set: { task.dueDate = $0 }), displayedComponents: [.date, .hourAndMinute])
            }
        }
        // Auto-save triggers
        .onChange(of: task.title) { _ in scheduleAutoSave() }
        .onChange(of: task.note) { _ in scheduleAutoSave() }
        .onChange(of: task.isCompleted) { _ in scheduleAutoSave() }
        .onChange(of: task.dueDate) { _ in scheduleAutoSave() }
        .onChange(of: task.durationMinutes) { _ in scheduleAutoSave() }
        .onDisappear { store.update(task) }
    }
}

// MARK: Keyword settings
private struct KeywordSettingsSheet: View {
    @EnvironmentObject var store: TaskStore
    @Environment(\.dismiss) private var dismiss
    @State private var key: String = ""
    @State private var category: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Add Mapping") {
                    TextField("Keyword (e.g., noori)", text: $key)
                    TextField("Category (e.g., AP GOV)", text: $category)
                    Button("Add / Update") {
                        guard !key.trimmingCharacters(in: .whitespaces).isEmpty,
                              !category.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        store.setMapping(key: key, category: category)
                        key = ""; category = ""
                    }
                }
                Section("Current Mappings") {
                    if store.keywordMap.isEmpty {
                        Text("No mappings yet").foregroundStyle(.secondary)
                    } else {
                        ForEach(store.keywordMap.sorted(by: { $0.key < $1.key }), id: \.key) { k, v in
                            HStack { Text(k); Spacer(); Text(v).foregroundStyle(.secondary) }
                                .swipeActions {
                                    Button(role: .destructive) { store.removeMapping(key: k) } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
            }
            .navigationTitle("Keyword Settings")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
    }
}
