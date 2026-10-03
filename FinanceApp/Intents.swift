import AppIntents
import SwiftUI
import Combine

// Siri / Shortcuts integration (App Intents).
//
// iOS 27's Siri drives third-party apps exclusively through App Intents; the same
// definitions power Shortcuts, Spotlight and the Action button on iOS 26 today.
// Policy: logging an expense is allowed hands-free (no sensitive data is revealed);
// anything that READS balances requires local device authentication.
//
// ⚠️ New top-level file — must be registered in the pbxproj on the Mac:
//     python3 scripts/register_intents.py   (after the cp -R source sync)
//
// Follow-ups that need the iOS 27 SDK: entity schemas for the Spotlight semantic
// index, View Annotations, and the App Intents testing framework.

// MARK: - Deep-link routing (intent → MainNavigationView)

@MainActor
final class NavigationRouter: ObservableObject {
    static let shared = NavigationRouter()
    @Published var pending: NavItem?
    @Published var showAddExpense = false   // set by the pfe://add widget deep link
    private init() {}
}

// MARK: - Shared helpers

private func defaultCurrency() -> Currency {
    let code = UserDefaults.standard.string(forKey: "defaultCurrencyCode") ?? "USD"
    return Currency.all.first { $0.code == code } ?? .usd
}

// MARK: - Section parameter

enum AppSection: String, AppEnum {
    case overview, expenses, investments, debt, recurring, search, settings

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Section"
    static var caseDisplayRepresentations: [AppSection: DisplayRepresentation] = [
        .overview: "Overview", .expenses: "Expenses", .investments: "Investments",
        .debt: "Debt", .recurring: "Recurring", .search: "Search", .settings: "Settings",
    ]

    var navItem: NavItem {
        switch self {
        case .overview:    return .dashboard
        case .expenses:    return .expenses
        case .investments: return .investments
        case .debt:        return .debt
        case .recurring:   return .recurring
        case .search:      return .search
        case .settings:    return .settings
        }
    }
}

// MARK: - Category entity (dynamic: prebuilt + user categories)

struct CategoryEntity: AppEntity {
    var id: String
    var name: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Category"
    static var defaultQuery = CategoryQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct CategoryQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [CategoryEntity] {
        await all().filter { identifiers.contains($0.id) }
    }

    func entities(matching string: String) async throws -> [CategoryEntity] {
        await all().filter { $0.name.localizedCaseInsensitiveContains(string) }
    }

    func suggestedEntities() async throws -> [CategoryEntity] {
        await all()
    }

    @MainActor
    private func all() async -> [CategoryEntity] {
        let user = (try? await CloudKitManager.shared.fetchUserCategories()) ?? []
        let builtInIDs = Set(ExpenseCategory.prebuilt.map(\.id))
        let merged = ExpenseCategory.prebuilt + user.filter { !builtInIDs.contains($0.id) }
        return merged.map { CategoryEntity(id: $0.id, name: $0.name) }
    }
}

// MARK: - Log an expense

struct AddExpenseIntent: AppIntent {
    static var title: LocalizedStringResource = "Log an Expense"
    static var description = IntentDescription("Adds an expense to Personal Finance Expert.")
    // Hands-free logging is deliberate: nothing sensitive is read back.
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    static var openAppWhenRun = false

    @Parameter(title: "Amount", requestValueDialog: "How much was it?")
    var amount: Double

    @Parameter(title: "Title", requestValueDialog: "What was it for?")
    var name: String

    @Parameter(title: "Category")
    var category: CategoryEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$amount) for \(\.$name)") {
            \.$category
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard amount > 0 else {
            throw $amount.needsValueError("How much was it?")
        }
        let expense = Expense(title: name,
                              amount: amount,
                              currencyCode: defaultCurrency().code,
                              categoryID: category?.id ?? "other")
        try await CloudKitManager.shared.saveExpense(expense)
        return .result(dialog: "Logged \(expense.formattedAmount) for \(name).")
    }
}

// MARK: - Spending this month

struct MonthSpendIntent: AppIntent {
    static var title: LocalizedStringResource = "Spending This Month"
    static var description = IntentDescription("Your total expenses for the current month.")
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Double> & ProvidesDialog {
        let cal = Calendar.current
        let now = Date()
        let expenses = (try? await CloudKitManager.shared.fetchExpenses()) ?? []
        let total = expenses
            .filter { cal.isDate($0.date, equalTo: now, toGranularity: .month) }
            .reduce(0) { $0 + $1.amount }
        let month = now.formatted(.dateTime.month(.wide))
        return .result(value: total,
                       dialog: "You've spent \(defaultCurrency().format(total)) in \(month).")
    }
}

// MARK: - Net worth

struct NetWorthIntent: AppIntent {
    static var title: LocalizedStringResource = "Net Worth"
    static var description = IntentDescription("Your investments minus your debts.")
    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Double> & ProvidesDialog {
        let inv = (try? await CloudKitManager.shared.fetchInvestments()) ?? []
        let deb = (try? await CloudKitManager.shared.fetchDebts()) ?? []
        let net = inv.reduce(0) { $0 + $1.currentValue }
                - deb.reduce(0) { $0 + $1.currentBalance }
        return .result(value: net,
                       dialog: "Your net worth is \(defaultCurrency().format(net)).")
    }
}

// MARK: - Open a section

struct OpenSectionIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Section"
    static var description = IntentDescription("Opens Personal Finance Expert to a section.")
    static var openAppWhenRun = true

    @Parameter(title: "Section")
    var section: AppSection

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$section)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        NavigationRouter.shared.pending = section.navItem
        return .result()
    }
}

// MARK: - App Shortcuts (also surfaces in Shortcuts, Spotlight, Action button)

struct FinanceAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddExpenseIntent(),
            phrases: [
                "Log an expense in \(.applicationName)",
                "Add an expense to \(.applicationName)",
                "Record spending in \(.applicationName)",
            ],
            shortTitle: "Log Expense",
            systemImageName: "plus.circle.fill"
        )
        AppShortcut(
            intent: MonthSpendIntent(),
            phrases: [
                "How much have I spent in \(.applicationName)",
                "Show my spending in \(.applicationName)",
            ],
            shortTitle: "This Month",
            systemImageName: "chart.bar.fill"
        )
        AppShortcut(
            intent: NetWorthIntent(),
            phrases: [
                "What's my net worth in \(.applicationName)",
                "Show my net worth in \(.applicationName)",
            ],
            shortTitle: "Net Worth",
            systemImageName: "chart.line.uptrend.xyaxis"
        )
        AppShortcut(
            intent: OpenSectionIntent(),
            phrases: [
                "Open a section in \(.applicationName)",
            ],
            shortTitle: "Open Section",
            systemImageName: "square.grid.2x2.fill"
        )
    }
}
