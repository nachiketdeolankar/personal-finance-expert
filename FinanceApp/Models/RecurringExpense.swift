import Foundation
import UserNotifications

enum RecurringFrequency: String, Codable, CaseIterable {
    case daily   = "Daily"
    case weekly  = "Weekly"
    case monthly = "Monthly"
    case yearly  = "Yearly"

    var calendarComponent: Calendar.Component {
        switch self {
        case .daily:   return .day
        case .weekly:  return .weekOfYear
        case .monthly: return .month
        case .yearly:  return .year
        }
    }
}

struct RecurringExpense: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var amount: Double
    var currencyCode: String
    var categoryID: String
    var frequency: RecurringFrequency
    var startDate: Date
    var endDate: Date?
    var notes: String
    var isActive: Bool
    var nextDueDate: Date

    init(
        id: String = UUID().uuidString,
        title: String,
        amount: Double,
        currencyCode: String = "USD",
        categoryID: String = "subscriptions",
        frequency: RecurringFrequency = .monthly,
        startDate: Date = Date(),
        endDate: Date? = nil,
        notes: String = "",
        isActive: Bool = true
    ) {
        self.id = id
        self.title = title
        self.amount = amount
        self.currencyCode = currencyCode
        self.categoryID = categoryID
        self.frequency = frequency
        self.startDate = startDate
        self.endDate = endDate
        self.notes = notes
        self.isActive = isActive
        self.nextDueDate = startDate
    }

    var currency: Currency {
        Currency.all.first { $0.code == currencyCode } ?? .usd
    }

    var formattedAmount: String {
        currency.format(amount)
    }

    mutating func advanceNextDueDate() {
        nextDueDate = Calendar.current.date(
            byAdding: frequency.calendarComponent,
            value: 1,
            to: nextDueDate
        ) ?? nextDueDate
    }
}

// MARK: - Local due-date reminders
// Local notifications only — push notifications can't provision on the free team.

@MainActor
final class RecurringReminders {
    static let shared = RecurringReminders()
    static let enabledKey = "recurringRemindersEnabled"

    private init() {}

    var isEnabled: Bool { UserDefaults.standard.bool(forKey: Self.enabledKey) }

    /// Asks the system for notification permission. Returns whether it was granted.
    func requestPermission() async -> Bool {
        let granted = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
        return granted ?? false
    }

    /// Replaces all pending reminders with one per active recurring expense,
    /// firing at 9:00 on its next due date. Call whenever the recurring list changes.
    func reschedule(for recurring: [RecurringExpense]) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        guard isEnabled else { return }
        for r in recurring where r.isActive && r.nextDueDate > Date() {
            var comps = Calendar.current.dateComponents([.year, .month, .day], from: r.nextDueDate)
            comps.hour = 9
            let content = UNMutableNotificationContent()
            content.title = "\(r.title) due today"
            content.body = "\(r.formattedAmount) · \(r.frequency.rawValue)"
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            center.add(UNNotificationRequest(identifier: r.id, content: content, trigger: trigger))
        }
    }
}
