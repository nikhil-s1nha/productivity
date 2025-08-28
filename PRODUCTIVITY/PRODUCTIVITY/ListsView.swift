import SwiftUI

struct ListsView: View {
    @EnvironmentObject private var store: TaskStore
    @State private var filter: TaskFilter = .all
    @State private var showingNew = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.filtered(filter)) { item in
                    NavigationLink {
                        TaskDetailView(task: item)
                    } label: {
                        TaskRow(item: item) {
                            store.toggle(item.id)
                        }
                    }
                }
                .onDelete(perform: store.delete)
            }
            .navigationTitle("Lists")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        Picker("Filter", selection: $filter) {
                            ForEach(TaskFilter.allCases) { f in
                                Text(f.rawValue).tag(f)
                            }
                        }
                    } label: {
                        // FIX: was using `due` (not in scope). Show current filter instead.
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
                    .presentationDetents([.medium, .large])
            }
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
                    ForEach(item.tags, id: \.self) { tag in
                        Text("#\(tag)").font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Color.secondary.opacity(0.15)))
                    }
                }
            }
        }
    }
}

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
