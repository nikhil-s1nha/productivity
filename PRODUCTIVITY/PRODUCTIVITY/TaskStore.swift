import Foundation
import Combine

// MARK: - Task Store (data only)
final class TaskStore: ObservableObject {
    @Published private(set) var tasks: [TaskItem] = []
    @Published var keywordMap: [String: String] = [:]   // e.g., "noori" -> "AP GOV"

    private let saveURL: URL
    private let keywordsURL: URL

    init() {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        saveURL = dir.appendingPathComponent("tasks.json")
        keywordsURL = dir.appendingPathComponent("keywords.json")
        load()
        loadKeywords()
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

    // MARK: - Keyword rules
    func setMapping(key: String, category: String) {
        keywordMap[key.lowercased()] = category
        saveKeywords()
    }

    func removeMapping(key: String) {
        keywordMap.removeValue(forKey: key.lowercased())
        saveKeywords()
    }

    // MARK: - Notes-style import with rules
    /// Each non-empty line becomes a task. Supports:
    /// - #tags
    /// - durations like [25m], [1h]
    /// - weekday phrases incl. "next <weekday>"
    /// - keywordMap tokens (e.g., "noori" -> "AP GOV"), removed from title and added as first tag
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

            // inline #tags
            let tagHits = matches(for: #"(?<=#)[A-Za-z0-9_\-]+"#, in: title)
            if !tagHits.isEmpty {
                tags.append(contentsOf: tagHits)
                for t in tagHits {
                    title = title.replacingOccurrences(of: "#\(t)", with: "").trimmingCharacters(in: .whitespaces)
                }
            }

            // inline durations like [25m] / [1h]
            if let durToken = matches(for: #"\[(\d+)(m|h)\]"#, in: title).first,
               let amt = Int(durToken.replacingOccurrences(of: #"\D"#, with: "", options: .regularExpression)) {
                duration = durToken.contains("h") ? (amt * 60) : amt
                title = title.replacingOccurrences(of: durToken, with: "").trimmingCharacters(in: .whitespaces)
            }

            // "next <weekday>" or plain weekday → due date
            if let span = matchWeekdaySpan(in: title) {
                due = span.isNext ? nextWeekday(span.weekday, from: .now) : next(weekday: span.weekday, from: .now)
                title.removeSubrange(span.rangeInOriginal(title))
                title = title.replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespaces)
            } else if let (name, wk) = firstWeekday(in: title) {
                due = next(weekday: wk, from: .now)
                title = title.replacingOccurrences(of: name, with: "", options: .caseInsensitive)
                    .trimmingCharacters(in: .whitespaces)
            }

            // keywordMap: token -> category tag (remove token from title)
            var words: [String] = []
            for w in title.split(separator: " ") {
                let lw = w.lowercased()
                if let cat = keywordMap[lw] {
                    if !tags.contains(cat) { tags.insert(cat, at: 0) } // first tag for section grouping
                } else {
                    words.append(String(w))
                }
            }
            title = words.joined(separator: " ")

            // build and save
            let item = TaskItem(
                id: UUID(),
                title: title,
                note: "",
                createdAt: .now,
                dueDate: due,
                scheduledStart: nil,
                durationMinutes: duration,
                isCompleted: false,
                tags: tags
            )
            add(item)
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

// MARK: - Weekday parsing helpers

fileprivate struct WeekdaySpan {
    let isNext: Bool
    let weekday: Int   // 1=Sun … 7=Sat (Calendar)
    let range: Range<String.Index>  // range in lowercased string
    func rangeInOriginal(_ original: String) -> Range<String.Index> {
        let lower = original.lowercased()
        let startOff = lower.distance(from: lower.startIndex, to: range.lowerBound)
        let endOff   = lower.distance(from: lower.startIndex, to: range.upperBound)
        let start = original.index(original.startIndex, offsetBy: startOff)
        let end   = original.index(original.startIndex, offsetBy: endOff)
        return start..<end
    }
}

fileprivate func matchWeekdaySpan(in text: String) -> WeekdaySpan? {
    let lower = text.lowercased()
    let tokens: [(String, Int)] = [
        ("sunday",1),("sun",1),
        ("monday",2),("mon",2),
        ("tuesday",3),("tues",3),("tue",3),
        ("wednesday",4),("weds",4),("wed",4),
        ("thursday",5),("thurs",5),("thur",5),("thu",5),
        ("friday",6),("fri",6),
        ("saturday",7),("sat",7)
    ]
    if let nextRange = lower.range(of: "next ") {
        let afterNext = nextRange.upperBound..<lower.endIndex
        for (name, wk) in tokens {
            if let r = lower.range(of: name, options: [.caseInsensitive], range: afterNext) {
                let span = nextRange.lowerBound..<r.upperBound
                return WeekdaySpan(isNext: true, weekday: wk, range: span)
            }
        }
    }
    for (name, wk) in tokens {
        if let r = lower.range(of: name, options: .caseInsensitive) {
            return WeekdaySpan(isNext: false, weekday: wk, range: r)
        }
    }
    return nil
}

fileprivate func firstWeekday(in text: String) -> (String, Int)? {
    let map: [(String, Int)] = [
        ("sunday",1),("sun",1),
        ("monday",2),("mon",2),
        ("tuesday",3),("tues",3),("tue",3),
        ("wednesday",4),("weds",4),("wed",4),
        ("thursday",5),("thurs",5),("thur",5),("thu",5),
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

/// next week's weekday (at least 7 days ahead)
fileprivate func nextWeekday(_ weekday: Int, from date: Date) -> Date {
    var comps = DateComponents()
    comps.weekday = weekday
    let cal = Calendar.current
    let upcoming = cal.nextDate(after: date, matching: comps, matchingPolicy: .nextTimePreservingSmallerComponents)!
    let plus7 = cal.date(byAdding: .day, value: 7, to: date)!
    if upcoming <= plus7 {
        return cal.date(byAdding: .day, value: 7, to: upcoming)!
    }
    return upcoming
}

// MARK: - Regex helper
fileprivate func matches(for regex: String, in text: String) -> [String] {
    (try? NSRegularExpression(pattern: regex))?
        .matches(in: text, range: NSRange(text.startIndex..., in: text))
        .compactMap { Range($0.range, in: text).map { String(text[$0]) } } ?? []
}
