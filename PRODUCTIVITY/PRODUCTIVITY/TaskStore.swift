import Foundation
import Combine

final class TaskStore: ObservableObject {
    @Published private(set) var tasks: [TaskItem] = []

    private let saveURL: URL

    init() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        saveURL = dir.appendingPathComponent("tasks.json")
        load()
    }

    // MARK: - CRUD

    func add(_ task: TaskItem) {
        tasks.insert(task, at: 0)
        save()
    }

    func toggle(_ id: UUID) {
        guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[i].isCompleted.toggle()
        save()
    }

    func update(_ task: TaskItem) {
        guard let i = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[i] = task
        save()
    }

    func delete(at offsets: IndexSet) {
        tasks.remove(atOffsets: offsets)
        save()
    }

    // MARK: - Filters

    func filtered(_ filter: TaskFilter) -> [TaskItem] {
        switch filter {
        case .all:
            return tasks.sorted { $0.createdAt > $1.createdAt }
        case .today:
            return tasks.filter { item in
                guard let start = item.scheduledStart ?? item.dueDate else { return false }
                return Calendar.current.isDateInToday(start)
            }.sorted { ($0.scheduledStart ?? $0.dueDate ?? .distantFuture) < ($1.scheduledStart ?? $1.dueDate ?? .distantFuture) }
        case .upcoming:
            return tasks.filter { ($0.dueDate ?? $0.scheduledStart) ?? .distantFuture > .now && !$0.isCompleted }
                .sorted { ($0.dueDate ?? $0.scheduledStart ?? .distantFuture) < ($1.dueDate ?? $1.scheduledStart ?? .distantFuture) }
        case .unplanned:
            return tasks.filter { $0.scheduledStart == nil && !$0.isCompleted }
        case .completed:
            return tasks.filter { $0.isCompleted }
        }
    }

    // MARK: - Notes-style parsing

    /// Parse a block of text like Notes. Each non-empty line becomes a task.
    /// Supports inline tags with #tag and optional duration like [25m] or [1h].
    func importFromText(_ text: String) {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        for line in lines {
            var title = line
            var tags: [String] = []
            var duration: Int? = nil

            // tags like #work #hw
            let tagMatches = matches(for: #"(?<=#)[A-Za-z0-9_-]+"#, in: title)
            tags = tagMatches
            for t in tagMatches { title = title.replacingOccurrences(of: "#\(t)", with: "").trimmingCharacters(in: .whitespaces) }

            // duration like [25m] [1h] [90m]
            if let durStr = matches(for: #"\[(\d+)(m|h)\]"#, in: title).first,
               let amount = Int(durStr.replacingOccurrences(of: #"\D"#, with: "", options: .regularExpression)) {
                let isHours = durStr.contains("h")
                duration = isHours ? amount * 60 : amount
                title = title.replacingOccurrences(of: durStr, with: "").trimmingCharacters(in: .whitespaces)
            }

            add(TaskItem(title: title, durationMinutes: duration, tags: tags))
        }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: saveURL) else { return }
        if let decoded = try? JSONDecoder().decode([TaskItem].self, from: data) {
            tasks = decoded
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(tasks) {
            try? data.write(to: saveURL, options: .atomic)
        }
    }
}

// simple regex helper
fileprivate func matches(for regex: String, in text: String) -> [String] {
    (try? NSRegularExpression(pattern: regex))?
        .matches(in: text, range: NSRange(text.startIndex..., in: text))
        .compactMap { Range($0.range, in: text).map { String(text[$0]) } } ?? []
}
