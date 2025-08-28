import Foundation

struct TaskItem: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var note: String = ""
    var createdAt: Date = .now
    var dueDate: Date? = nil
    var scheduledStart: Date? = nil      // for timeboxing
    var durationMinutes: Int? = nil      // for timeboxing (e.g., 25, 45, 60)
    var isCompleted: Bool = false
    var tags: [String] = []
}

enum TaskFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case today = "Today"
    case upcoming = "Upcoming"
    case unplanned = "Unplanned"
    case completed = "Completed"

    var id: String { rawValue }
}
