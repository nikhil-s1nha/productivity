import Foundation
import EventKit

final class EventKitManager {
    static let shared = EventKitManager()
    private let store = EKEventStore()

    private init() {}

    func requestAccess(completion: @escaping (Bool) -> Void) {
        store.requestAccess(to: .event) { ok, _ in
            completion(ok)
        }
    }

    func createCalendarEvent(for task: TaskItem) {
        requestAccess { ok in
            guard ok, let start = task.scheduledStart, let dur = task.durationMinutes else { return }
            let event = EKEvent(eventStore: self.store)
            event.title = task.title
            event.notes = task.note
            event.startDate = start
            event.endDate = start.addingTimeInterval(TimeInterval(dur * 60))
            event.calendar = self.store.defaultCalendarForNewEvents
            try? self.store.save(event, span: .thisEvent)
        }
    }

    // Reminders are also in EventKit; uncomment if you want this too
    /*
    func createReminder(for task: TaskItem) {
        store.requestAccess(to: .reminder) { ok, _ in
            guard ok else { return }
            let reminder = EKReminder(eventStore: self.store)
            reminder.title = task.title
            reminder.notes = task.note
            if let due = task.dueDate {
                reminder.dueDateComponents = Calendar.current.dateComponents([.year,.month,.day,.hour,.minute], from: due)
            }
            reminder.calendar = self.store.defaultCalendarForNewReminders()
            try? self.store.save(reminder, commit: true)
        }
    }
    */
}
