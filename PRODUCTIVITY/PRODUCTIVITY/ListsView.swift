import SwiftUI

private struct TaskSection: Identifiable {
    let id: String
    var items: [TaskItem]
}

struct ListsView: View {
    @EnvironmentObject var store: TaskStore
    @State private var filter: TaskFilter = .all
    @State private var showingNew = false
    @State private var showingSettings = false
    @State private var listMode: Int = 0 // 0 = Active, 1 = Completed

    var body: some View {
        NavigationStack {
            List {
                ForEach(groupedSections) { section in
                    SectionGroupView(
                        section: section,
                        onToggle: { id in
                            withAnimation { store.toggle(id) }
                        },
                        onDelete: { offsets in
                            deleteFromStore(offsets, in: section.items)
                        }
                    )
                }
            }
            .navigationTitle("Lists")
            .toolbar {
                // Center segmented control for Active / Completed
                ToolbarItem(placement: .principal) {
                    Picker("", selection: $listMode) {
                        Text("Active").tag(0)
                        Text("Completed").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        Picker("Filter", selection: $filter) {
                            ForEach(TaskFilter.allCases) { f in
                                Text(f.rawValue).tag(f)
                            }
                        }
                        Divider()
                        Button("Keyword Settings…") { showingSettings = true }
                    } label: {
                        Label(filter.rawValue, systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showingNew = true } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                }
            }
            .sheet(isPresented: $showingNew) {
                NewTaskSheet { store.add($0) }
            }
            .sheet(isPresented: $showingSettings) {
                KeywordSettingsSheet().environmentObject(store)
            }
        }
    }

    private var filteredItems: [TaskItem] {
        let tasks = store.tasks
        let base: [TaskItem]
        switch filter {
        case .all:
            base = tasks.sorted { $0.createdAt > $1.createdAt }
        case .today:
            base = tasks.filter { item in
                let date = item.scheduledStart ?? item.dueDate
                return date.map(Calendar.current.isDateInToday) ?? false
            }.sorted { ($0.scheduledStart ?? $0.dueDate ?? .distantFuture) < ($1.scheduledStart ?? $1.dueDate ?? .distantFuture) }
        case .upcoming:
            base = tasks.filter { (($0.dueDate ?? $0.scheduledStart) ?? .distantFuture) > .now }
                .sorted { ($0.dueDate ?? $0.scheduledStart ?? .distantFuture) < ($1.dueDate ?? $1.scheduledStart ?? .distantFuture) }
        case .unplanned:
            base = tasks.filter { $0.scheduledStart == nil }
        case .completed:
            base = tasks // will be narrowed by listMode below
        }
        // Apply listMode (Active vs Completed)
        if listMode == 1 {
            return base.filter { $0.isCompleted }
        } else {
            return base.filter { !$0.isCompleted }
        }
    }

    private var groupedSections: [TaskSection] {
        let groups = Dictionary(grouping: filteredItems) { (item: TaskItem) in
            item.tags.first ?? "Other"
        }
        let sortedKeys = groups.keys.sorted()
        return sortedKeys.map { key in
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
        let globalIndices = store.tasks.enumerated().compactMap { (idx, t) in
            ids.contains(t.id) ? idx : nil
        }
        store.delete(at: IndexSet(globalIndices))
    }
}

private struct SectionGroupView: View {
    let section: TaskSection
    let onToggle: (UUID) -> Void
    let onDelete: (IndexSet) -> Void

    var body: some View {
        Section(header: Text(section.id).font(.title3).bold()) {
            ForEach(section.items) { item in
                HStack(alignment: .top, spacing: 12) {
                    // Small fixed hit-area circle button
                    Button(action: { onToggle(item.id) }) {
                        Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(item.isCompleted ? .green : .secondary)
                            .frame(width: 28, height: 28, alignment: .center)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain) // prevent row-wide highlight
                    // Dedicated link area (no overlay on the button)
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
                                    Label {
                                        Text(due, format: .dateTime.month().day().hour().minute())
                                            .font(.caption)
                                    } icon: {
                                        Image(systemName: "calendar")
                                    }
                                    .labelStyle(.titleAndIcon)
                                }
                                if let d = item.durationMinutes {
                                    Label("\(d)m", systemImage: "timer")
                                        .font(.caption)
                                }
                            }
                        }
                        .contentShape(Rectangle())
                    }
                }
                // Swipe right to complete/uncomplete
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button {
                        onToggle(item.id)
                    } label: {
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

private struct TaskRow: View {
    let item: TaskItem
    var onToggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.isCompleted ? .green : .secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.body.weight(.medium))
                    .strikethrough(item.isCompleted, color: .secondary)

                if !item.note.isEmpty {
                    Text(item.note).font(.subheadline).foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    if let due = item.dueDate {
                        Label {
                            Text(due, format: .dateTime.month().day().hour().minute())
                                .font(.caption)
                        } icon: {
                            Image(systemName: "calendar")
                        }
                        .labelStyle(.titleAndIcon)
                    }
                    if let d = item.durationMinutes {
                        Label("\(d)m", systemImage: "timer")
                            .font(.caption)
                    }
                }
            }
        }
    }
}

// NewTaskSheet, TaskDetailView, KeywordSettingsSheet remain unchanged from your file.

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

                Toggle("Due date", isOn: Binding(
                    get: { due != nil },
                    set: { due = $0 ? .now : nil }
                ))
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

private struct TaskDetailView: View {
    @EnvironmentObject private var store: TaskStore
    @State var task: TaskItem

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
                }, set: { new in
                    task.dueDate = new
                }), displayedComponents: [.date, .hourAndMinute])
                .opacity(task.dueDate == nil ? 0.3 : 1)
                .overlay(
                    Toggle("", isOn: Binding(get: { task.dueDate != nil }, set: { on in
                        task.dueDate = on ? .now : nil
                    })).labelsHidden()
                    , alignment: .trailing
                )

                Stepper(value: Binding(get: { task.durationMinutes ?? 0 }, set: { task.durationMinutes = $0 == 0 ? nil : $0 }),
                        in: 0...600, step: 5) {
                    Text("Duration: \(task.durationMinutes ?? 0)m")
                }
            }
        }
        .navigationTitle("Task")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { store.update(task) }
            }
        }
    }
}

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
