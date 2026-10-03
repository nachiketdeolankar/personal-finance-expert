import Foundation
import Combine
import SwiftUI

@MainActor
final class ExpenseViewModel: ObservableObject {
    @Published var expenses: [Expense] = []
    @Published var recurringExpenses: [RecurringExpense] = []
    @Published var categories: [ExpenseCategory] = ExpenseCategory.prebuilt
    @Published var budgets: [Budget] = []
    @Published var isLoading: Bool = false
    @Published var error: String?

    private let ck = CloudKitManager.shared
    private var settings: AppSettings

    init(settings: AppSettings = AppSettings()) {
        self.settings = settings
    }

    // MARK: - Load

    func loadAll() async {
        isLoading = true
        defer { isLoading = false }
        error = nil

        async let expensesFetch   = ck.fetchExpenses()
        async let recurringFetch  = ck.fetchRecurringExpenses()
        async let budgetsFetch    = ck.fetchBudgets()
        async let categoriesFetch = ck.fetchUserCategories()

        do {
            let (exp, rec, bud, userCats) = try await (expensesFetch, recurringFetch, budgetsFetch, categoriesFetch)
            expenses = exp
            recurringExpenses = rec
            budgets = bud
            // Merge prebuilt + user-created, deduplicating by id
            let builtInIDs = Set(ExpenseCategory.prebuilt.map(\.id))
            let filteredUser = userCats.filter { !builtInIDs.contains($0.id) }
            categories = ExpenseCategory.prebuilt + filteredUser
            RecurringReminders.shared.reschedule(for: recurringExpenses)
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Expenses

    func addExpense(_ expense: Expense) async {
        do {
            try await ck.saveExpense(expense)
            expenses.insert(expense, at: 0)
            ck.rememberMerchant(expense.title, categoryID: expense.categoryID)
            checkBudgetAlerts(for: expense)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func updateExpense(_ expense: Expense) async {
        do {
            try await ck.saveExpense(expense)
            if let idx = expenses.firstIndex(where: { $0.id == expense.id }) {
                expenses[idx] = expense
            }
            ck.rememberMerchant(expense.title, categoryID: expense.categoryID)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func deleteExpense(_ expense: Expense) async {
        do {
            try await ck.deleteExpense(expense)
            expenses.removeAll { $0.id == expense.id }
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Recurring

    func addRecurringExpense(_ r: RecurringExpense) async {
        do {
            try await ck.saveRecurringExpense(r)
            recurringExpenses.append(r)
            RecurringReminders.shared.reschedule(for: recurringExpenses)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func deleteRecurringExpense(_ r: RecurringExpense) async {
        do {
            try await ck.deleteRecurringExpense(r)
            recurringExpenses.removeAll { $0.id == r.id }
            RecurringReminders.shared.reschedule(for: recurringExpenses)
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Budgets

    func saveBudget(_ budget: Budget) async {
        do {
            try await ck.saveBudget(budget)
            if let idx = budgets.firstIndex(where: {
                $0.categoryID == budget.categoryID && $0.month == budget.month && $0.year == budget.year
            }) {
                budgets[idx] = budget
            } else {
                budgets.append(budget)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func deleteBudget(_ budget: Budget) async {
        do {
            try await ck.deleteBudget(budget)
            budgets.removeAll { $0.id == budget.id }
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Categories

    func addCategory(_ category: ExpenseCategory) async {
        do {
            try await ck.saveCategory(category)
            categories.append(category)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func deleteCategory(_ category: ExpenseCategory) async {
        guard !category.isSystem else { return }
        do {
            try await ck.deleteCategory(id: category.id)
            categories.removeAll { $0.id == category.id }
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Analytics helpers

    func expenses(for month: Int, year: Int) -> [Expense] {
        expenses.filter {
            let c = Calendar.current
            return c.component(.month, from: $0.date) == month &&
                   c.component(.year, from: $0.date) == year
        }
    }

    func totalSpent(for categoryID: String, month: Int, year: Int) -> Double {
        expenses(for: month, year: year)
            .filter { $0.categoryID == categoryID }
            .reduce(0) { $0 + $1.amount }
    }

    /// Average monthly spend for a category over the previous three full months
    /// (current month excluded), rounded up to the nearest 10. Nil if never spent.
    func suggestedBudget(for categoryID: String) -> Double? {
        let cal = Calendar.current
        var total: Double = 0
        for offset in 1...3 {
            guard let d = cal.date(byAdding: .month, value: -offset, to: Date()) else { continue }
            total += totalSpent(for: categoryID,
                                month: cal.component(.month, from: d),
                                year: cal.component(.year, from: d))
        }
        guard total > 0 else { return nil }
        return (total / 3 / 10).rounded(.up) * 10
    }

    func budget(for categoryID: String, month: Int, year: Int) -> Budget? {
        budgets.first { $0.categoryID == categoryID && $0.month == month && $0.year == year }
    }

    func budgetProgress(for categoryID: String, month: Int, year: Int) -> Double {
        guard let b = budget(for: categoryID, month: month, year: year), b.limitAmount > 0 else { return 0 }
        return totalSpent(for: categoryID, month: month, year: year) / b.limitAmount
    }

    var monthlyTotal: Double {
        let now = Date()
        let m = Calendar.current.component(.month, from: now)
        let y = Calendar.current.component(.year, from: now)
        return expenses(for: m, year: y).reduce(0) { $0 + $1.amount }
    }

    var spendingByCategory: [(category: ExpenseCategory, amount: Double)] {
        let now = Date()
        let m = Calendar.current.component(.month, from: now)
        let y = Calendar.current.component(.year, from: now)
        return categories.compactMap { cat in
            let total = totalSpent(for: cat.id, month: m, year: y)
            return total > 0 ? (category: cat, amount: total) : nil
        }.sorted { $0.amount > $1.amount }
    }

    func dailySpending(for month: Int, year: Int) -> [(day: Int, amount: Double)] {
        let monthExpenses = expenses(for: month, year: year)
        var byDay: [Int: Double] = [:]
        for exp in monthExpenses {
            let day = Calendar.current.component(.day, from: exp.date)
            byDay[day, default: 0] += exp.amount
        }
        return byDay.map { (day: $0.key, amount: $0.value) }.sorted { $0.day < $1.day }
    }

    // MARK: - Budget Alerts

    @Published var budgetAlerts: [(category: ExpenseCategory, progress: Double)] = []

    private func checkBudgetAlerts(for expense: Expense) {
        let now = Date()
        let m = Calendar.current.component(.month, from: now)
        let y = Calendar.current.component(.year, from: now)
        let progress = budgetProgress(for: expense.categoryID, month: m, year: y)
        let threshold = settings.budgetAlertThreshold

        if progress >= threshold {
            if let cat = categories.first(where: { $0.id == expense.categoryID }) {
                budgetAlerts.append((category: cat, progress: progress))
            }
        }
    }

    // MARK: - Category helper

    func category(for id: String) -> ExpenseCategory {
        categories.first { $0.id == id } ?? ExpenseCategory(
            id: id, name: "Unknown", iconName: "questionmark.circle", colorHex: "#B2BEC3", isSystem: false
        )
    }

    // MARK: - Clear all data

    func clearAllData() {
        ck.clearAllData()
        expenses = []
        recurringExpenses = []
        budgets = []
        categories = ExpenseCategory.prebuilt
        budgetAlerts = []
    }
}
