// TaskStore.swift
import Foundation
import Combine

final class TaskStore: ObservableObject {
    @Published private(set) var tasks: [TaskItem] = []
    @Published var keywordMap: [String: String] = [:]   // e.g., "noori" -> "History"

    private let saveURL: URL
    private let keywordsURL: URL

    init() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        saveURL = dir.appendingPathComponent("tasks.json")
        keywordsURL = dir.appendingPathComponent("keywords.json")
        load()
        loadKeywords()
    }

    // MARK: - CRUD (unchanged)
    func add(_ task: TaskItem) {
        tasks.insert(task, at: 0)
        save()
    }
    func toggle(_ id: UUID) { guard let i = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[i].isCompleted.toggle(); save()
    }
    func update(_ task: TaskItem) { guard let i = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[i] = task; save()
    }
    func delete(at offsets: IndexSet) { tasks.remove(atOffsets: offsets); save() }

    // MARK: - Filters (leave your version)

    // MARK: - Keyword map
    func setMapping(key: String, category: String) {
        keywordMap[key.lowercased()] = category
        saveKeywords()
    }
    func removeMapping(key: String) {
        keywordMap.removeValue(forKey: key.lowercased())
        saveKeywords()
    }

    // MARK: - Notes-style import with rules
    func importFromText(_ text: String) {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        for raw in lines {
            var title = raw
            var tags: [String] = []
            var due: Date? = nil
            var duration: Int? = nil

            // inline durations like [25m] [1h] (keep your existing logic if you have it)
            if let durToken = matches(for: #"\[(\d+)(m|h)\]"#, in: title).first,
               let amt = Int(durToken.replacingOccurrences(of: #"\D"#, with: "", options: .regularExpression)) {
                duration = durToken.contains("h") ? amt * 60 : amt
                title = title.replacingOccurrences(of: durToken, with: "").trimmingCharacters(in: .whitespaces)
            }

            // weekday → due date (next occurrence)
            if let (name, wk) = firstWeekday(in: title) {
                due = next(weekday: wk, from: .now)
                title = title.replacingOccurrences(of: name, with: "", options: .caseInsensitive)
                    .trimmingCharacters(in: .whitespaces)
            }

            // teacher/club → category tag, remove token
            var words: [String] = []
            for w in title.split(separator: " ") {
                let lw = w.lowercased()
                if let cat = keywordMap[lw] {
                    if !tags.contains(cat) { tags.append(cat) }
                } else {
                    words.append(String(w))
                }
            }
            title = words.joined(separator: " ")

            add(TaskItem(title: title, note: "", createdAt: .now,
                         dueDate: due, scheduledStart: nil, durationMinutes: duration,
                         isCompleted: false, tags: tags))
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
    private func loadKeywords() {
        guard let data = try? Data(contentsOf: keywordsURL) else { return }
        if let decoded = try? JSONDecoder().decode([String:String].self, from: data) {
            keywordMap = decoded
        }
    }
    private func saveKeywords() {
        if let data = try? JSONEncoder().encode(keywordMap) {
            try? data.write(to: keywordsURL, options: .atomic)
        }
    }
}

// Helpers
fileprivate func matches(for regex: String, in text: String) -> [String] {
    (try? NSRegularExpression(pattern: regex))?
        .matches(in: text, range: NSRange(text.startIndex..., in: text))
        .compactMap { Range($0.range, in: text).map { String(text[$0]) } } ?? []
}

fileprivate func firstWeekday(in text: String) -> (String, Int)? {
    // 1=Sun ... 7=Sat (Calendar.current)
    let map: [(String, Int)] = [
        ("sunday",1),("sun",1),
        ("monday",2),("mon",2),
        ("tuesday",3),("tue",3),("tues",3),
        ("wednesday",4),("wed",4),
        ("thursday",5),("thu",5),("thur",5),("thurs",5),
        ("friday",6),("fri",6),
        ("saturday",7),("sat",7)
    ]
    let lower = text.lowercased()
    for (name, num) in map where lower.contains(name) { return (name, num) }
    return nil
}
fileprivate func next(weekday: Int, from date: Date) -> Date {
    var comps = DateComponents()
    comps.weekday = weekday
    return Calendar.current.nextDate(after: date, matching: comps,
                                     matchingPolicy: .nextTimePreservingSmallerComponents)!
}
