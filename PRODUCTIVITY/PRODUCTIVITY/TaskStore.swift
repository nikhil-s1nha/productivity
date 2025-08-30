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

            // relative day tokens → due date (minimal: tomorrow / yesterday / today)
            do {
                let lower = title.lowercased()
                if lower.contains("tomorrow") || lower.contains("tmr") || lower.contains("tmrw") {
                    if let date = Calendar.current.date(byAdding: .day, value: 1, to: .now) {
                        due = startOfDay(date)
                    }
                    ["tomorrow","tmr","tmrw"].forEach { tok in
                        title = title.replacingOccurrences(of: tok, with: "", options: .caseInsensitive)
                    }
                    title = title.replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespaces)
                } else if lower.contains("today") {
                    due = startOfDay(.now)
                    title = title.replacingOccurrences(of: "today", with: "", options: .caseInsensitive)
                        .replacingOccurrences(of: "  ", with: " ")
                        .trimmingCharacters(in: .whitespaces)
                } else if lower.contains("yesterday") {
                    if let date = Calendar.current.date(byAdding: .day, value: -1, to: .now) {
                        due = startOfDay(date)
                    }
                    title = title.replacingOccurrences(of: "yesterday", with: "", options: .caseInsensitive)
                        .replacingOccurrences(of: "  ", with: " ")
                        .trimmingCharacters(in: .whitespaces)
                }
            }

            // "next <weekday>" or plain weekday → due date
            if let span = matchWeekdaySpan(in: title) {
                due = span.isNext ? nextWeekday(span.weekday, from: .now) : next(weekday: span.weekday, from: .now)
                if let d = due { due = startOfDay(d) }
                title.removeSubrange(span.rangeInOriginal(title))
                title = title.replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespaces)
            } else if let (name, wk) = firstWeekday(in: title) {
                due = next(weekday: wk, from: .now)
                if let d = due { due = startOfDay(d) }
                title = title.replacingOccurrences(of: name, with: "", options: .caseInsensitive)
                    .trimmingCharacters(in: .whitespaces)
            }
            
            // meetings: classify and optionally schedule into timebox
            var isMeeting = false
            var meetingType: String?
            do {
                let lower = title.lowercased()
                // detect "meeting" or "mtg"
                if lower.contains(" meeting") || lower.contains(" mtg") || lower.hasSuffix("meeting") || lower.hasSuffix("mtg") {
                    isMeeting = true
                    // capture word before meeting: e.g., "rocketry meeting"
                    let typePattern = #"(?i)\b([A-Za-z0-9\-]+)\s+(meeting|mtg)\b"#
                    if let m = try? NSRegularExpression(pattern: typePattern)
                        .firstMatch(in: title, range: NSRange(title.startIndex..<title.endIndex, in: title)),
                       let r1 = m.range(at: 1).location != NSNotFound ? Range(m.range(at: 1), in: title) : nil {
                        meetingType = String(title[r1]).lowercased()
                    }
                    // strip the literal word "meeting"/"mtg" from the title
                    title = title.replacingOccurrences(of: #"(?i)\b(meeting|mtg)\b"#, with: "", options: .regularExpression)
                        .replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespaces)
                }
            }
            // If it's a meeting, try to parse a time range "10 - 12", "10pm-12pm", etc.
            if isMeeting {
                let baseDay: Date = (due != nil) ? startOfDay(due!) : startOfDay(.now)
                let rangePattern = #"(?i)\b(\d{1,2})(?::(\d{2}))?\s*(am|pm|a|p)?\s*-\s*(\d{1,2})(?::(\d{2}))?\s*(am|pm|a|p)?\b"#
                if let rangeRegex = try? NSRegularExpression(pattern: rangePattern) {
                    let r = NSRange(title.startIndex..<title.endIndex, in: title)
                    if let m = rangeRegex.firstMatch(in: title, range: r) {
                        func to24h(_ hStr: String, _ mStr: String?, _ md: String?) -> (Int, Int) {
                            var h = Int(hStr) ?? 0
                            let mm = Int(mStr ?? "0") ?? 0
                            var isPM = false
                            var isAM = false
                            if let md = md?.lowercased() {
                                if md == "pm" || md == "p" { isPM = true }
                                if md == "am" || md == "a" { isAM = true }
                            } else {
                                // default PM when unspecified
                                isPM = true
                            }
                            if isAM {
                                if h == 12 { h = 0 }
                            } else if isPM {
                                if h != 12 { h += 12 }
                            }
                            return (h, mm)
                        }
                        // groups: 1 hour, 2 minute, 3 md ; 4 hour, 5 minute, 6 md
                        let h1 = Range(m.range(at: 1), in: title).map { String(title[$0]) } ?? "0"
                        let m1 = Range(m.range(at: 2), in: title).map { String(title[$0]) }
                        let md1 = Range(m.range(at: 3), in: title).map { String(title[$0]) }
                        let h2 = Range(m.range(at: 4), in: title).map { String(title[$0]) } ?? "0"
                        let m2 = Range(m.range(at: 5), in: title).map { String(title[$0]) }
                        let md2 = Range(m.range(at: 6), in: title).map { String(title[$0]) }
                        let (sh, sm) = to24h(h1, m1, md1)
                        let (eh, em) = to24h(h2, m2, md2)
                        if let startDate = Calendar.current.date(bySettingHour: sh, minute: sm, second: 0, of: baseDay),
                           let endDate = Calendar.current.date(bySettingHour: eh, minute: em, second: 0, of: baseDay) {
                            // assign scheduled start/duration for timebox
                            duration = max(0, Int(endDate.timeIntervalSince(startDate) / 60))
                            due = startDate
                        }
                        // strip the matched range token
                        if let rr = Range(m.range(at: 0), in: title) {
                            title.removeSubrange(rr)
                            title = title.replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespaces)
                        }
                    }
                }
                // add meeting tags
                if !tags.contains("meeting") { tags.append("meeting") }
                if let t = meetingType, !t.isEmpty { tags.append("meeting:\(t)") }
            }

            // time tokens → set time on due date (assume PM if no am/pm)
            do {
                let pattern = #"(?i)\b(\d{1,2})(?::(\d{2}))?\s*(am|pm|a|p)?\b"#
                guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
                let range = NSRange(title.startIndex..<title.endIndex, in: title)
                if let match = regex.firstMatch(in: title, range: range),
                   match.numberOfRanges >= 2,
                   let hourRange = Range(match.range(at: 1), in: title) {
                    let hourStr = String(title[hourRange])
                    let minuteStr: String = {
                        if let mr = Range(match.range(at: 2), in: title) {
                            return String(title[mr])
                        } else { return "0" }
                    }()
                    let meridiem: String? = {
                        if let mr = Range(match.range(at: 3), in: title) {
                            return String(title[mr]).lowercased()
                        } else { return nil }
                    }()
                    if var hour = Int(hourStr), let minute = Int(minuteStr) {
                        var isPM = false
                        var isAM = false
                        if let m = meridiem {
                            if m == "pm" || m == "p" { isPM = true }
                            if m == "am" || m == "a" { isAM = true }
                        } else {
                            // default to PM when not specified
                            isPM = true
                        }
                        // normalize 12 AM/PM
                        if isAM {
                            if hour == 12 { hour = 0 }
                        } else if isPM {
                            if hour != 12 { hour += 12 }
                        }
                        // decide base date
                        let base: Date = due ?? .now
                        if let set = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: base) {
                            due = set
                        }
                        // strip the time token from title
                        let tokenRange = Range(match.range(at: 0), in: title)!
                        title.removeSubrange(tokenRange)
                        title = title.replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespaces)
                        if isMeeting {
                            // if we parsed a single time, use it as scheduled start; set default 60m if no duration yet
                            // (Timebox uses scheduledStart; we store time in 'due' then copy in build step below)
                            if duration == nil { duration = 60 }
                        }
                    }
                }
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
            // If this was a meeting and we have a time component, schedule it; else leave scheduledStart nil.
            let hasTime: Bool = {
                guard let d = due else { return false }
                let c = Calendar.current.dateComponents([.hour,.minute,.second], from: d)
                return (c.hour ?? 0) != 0 || (c.minute ?? 0) != 0 || (c.second ?? 0) != 0
            }()
            let item = TaskItem(
                id: UUID(),
                title: title,
                note: "",
                createdAt: .now,
                dueDate: hasTime ? nil : due,          // if timebox scheduled, keep dueDate nil (timebox shows it)
                scheduledStart: hasTime ? due : nil,   // timebox start when time was provided
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
    let dt = Calendar.current.nextDate(after: date, matching: comps,
                                       matchingPolicy: .nextTimePreservingSmallerComponents)!
    return startOfDay(dt)
}

/// next week's weekday (at least 7 days ahead)
fileprivate func nextWeekday(_ weekday: Int, from date: Date) -> Date {
    var comps = DateComponents()
    comps.weekday = weekday
    let cal = Calendar.current
    let upcoming = cal.nextDate(after: date, matching: comps, matchingPolicy: .nextTimePreservingSmallerComponents)!
    let plus7 = cal.date(byAdding: .day, value: 7, to: date)!
    if upcoming <= plus7 {
        return startOfDay(cal.date(byAdding: .day, value: 7, to: upcoming)!)
    }
    return startOfDay(upcoming)
}

// MARK: - Regex helper
fileprivate func matches(for regex: String, in text: String) -> [String] {
    (try? NSRegularExpression(pattern: regex))?
        .matches(in: text, range: NSRange(text.startIndex..., in: text))
        .compactMap { Range($0.range, in: text).map { String(text[$0]) } } ?? []
}

fileprivate func startOfDay(_ date: Date) -> Date {
    Calendar.current.startOfDay(for: date)
}
 
