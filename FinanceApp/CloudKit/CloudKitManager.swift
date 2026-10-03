import Foundation
import Combine
import WidgetKit

// Local JSON-backed store with the same interface as the CloudKit version.
// Swap this file for CloudKitManager+CloudKit.swift when a paid developer
// account is available and iCloud capability is added.

// Written by the app, read by the widget extension (which compiles its own copy —
// keep the two definitions' coding keys in sync; see PersonalFinanceWidgets/).
struct WidgetSnapshot: Codable {
    var date: Date
    var currencyCode: String
    var maskAmounts: Bool
    var netWorth: Double
    var netWorthDeltaPercent: Double?
    var history: [Double]              // recent net-worth values, oldest → newest
    var monthSpent: Double
    var monthBudget: Double            // sum of this month's budget limits (0 = none set)
    var budgets: [BudgetStat]          // top 3 by usage
    var budgetsOnTrack: Int
    var budgetsTotal: Int
    var bills: [Bill]                  // next 3 due
    var billsThisWeekCount: Int
    var billsThisWeekTotal: Double
    var biggestExpenseTitle: String?
    var biggestExpenseAmount: Double?

    struct BudgetStat: Codable { var name: String; var spent: Double; var limit: Double }
    struct Bill: Codable { var title: String; var amount: Double; var date: Date }
}

struct NetWorthSnapshot: Codable, Identifiable, Hashable {
    var id: String = UUID().uuidString
    var date: Date
    var investments: Double
    var debts: Double
    var netWorth: Double
}

enum CloudKitError: LocalizedError {
    case saveFailed(Error)
    case fetchFailed(Error)
    case deleteFailed(Error)
    case notAuthenticated

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:    return "iCloud not available."
        case .saveFailed(let e):   return "Save failed: \(e.localizedDescription)"
        case .fetchFailed(let e):  return "Fetch failed: \(e.localizedDescription)"
        case .deleteFailed(let e): return "Delete failed: \(e.localizedDescription)"
        }
    }
}

@MainActor
final class CloudKitManager: ObservableObject {
    static let shared = CloudKitManager()

    @Published var isSyncing: Bool = false
    @Published var syncError: CloudKitError?

    // Surfaced so SettingsView can show status
    var iCloudStatus: Int { 1 }   // placeholder — always "available" locally

    private let store = LocalJSONStore.shared

    private init() {}

    func checkAccountStatus() async {}
    func setupSubscriptions() async {}

    // MARK: - Expenses

    func saveExpense(_ expense: Expense) async throws {
        isSyncing = true
        defer { isSyncing = false }
        var all = try load([Expense].self, key: .expenses)
        all.removeAll { $0.id == expense.id }
        all.insert(expense, at: 0)
        try save(all, key: .expenses)
    }

    func fetchExpenses() async throws -> [Expense] {
        return try load([Expense].self, key: .expenses)
    }

    func deleteExpense(_ expense: Expense) async throws {
        var all = try load([Expense].self, key: .expenses)
        all.removeAll { $0.id == expense.id }
        try save(all, key: .expenses)
    }

    // MARK: - Recurring

    func saveRecurringExpense(_ r: RecurringExpense) async throws {
        var all = try load([RecurringExpense].self, key: .recurring)
        all.removeAll { $0.id == r.id }
        all.append(r)
        try save(all, key: .recurring)
    }

    func fetchRecurringExpenses() async throws -> [RecurringExpense] {
        return try load([RecurringExpense].self, key: .recurring)
    }

    func deleteRecurringExpense(_ r: RecurringExpense) async throws {
        var all = try load([RecurringExpense].self, key: .recurring)
        all.removeAll { $0.id == r.id }
        try save(all, key: .recurring)
    }

    // MARK: - Budgets

    func saveBudget(_ budget: Budget) async throws {
        var all = try load([Budget].self, key: .budgets)
        all.removeAll { $0.id == budget.id }
        all.append(budget)
        try save(all, key: .budgets)
    }

    func fetchBudgets() async throws -> [Budget] {
        return try load([Budget].self, key: .budgets)
    }

    func deleteBudget(_ budget: Budget) async throws {
        var all = try load([Budget].self, key: .budgets)
        all.removeAll { $0.id == budget.id }
        try save(all, key: .budgets)
    }

    // MARK: - Categories

    func saveCategory(_ category: ExpenseCategory) async throws {
        var all = try load([ExpenseCategory].self, key: .categories)
        all.removeAll { $0.id == category.id }
        all.append(category)
        try save(all, key: .categories)
    }

    func fetchUserCategories() async throws -> [ExpenseCategory] {
        return try load([ExpenseCategory].self, key: .categories)
    }

    func deleteCategory(id: String) async throws {
        var all = try load([ExpenseCategory].self, key: .categories)
        all.removeAll { $0.id == id }
        try save(all, key: .categories)
    }

    // MARK: - Helpers

    // MARK: - Investments

    func saveInvestment(_ investment: Investment) async throws {
        var all = try load([Investment].self, key: .investments)
        all.removeAll { $0.id == investment.id }
        all.insert(investment, at: 0)
        try save(all, key: .investments)
        await recordNetWorthSnapshot()
    }

    func fetchInvestments() async throws -> [Investment] {
        try load([Investment].self, key: .investments)
    }

    func deleteInvestment(_ investment: Investment) async throws {
        var all = try load([Investment].self, key: .investments)
        all.removeAll { $0.id == investment.id }
        try save(all, key: .investments)
        await recordNetWorthSnapshot()
    }

    // MARK: - Debts

    func saveDebt(_ debt: Debt) async throws {
        var all = try load([Debt].self, key: .debts)
        all.removeAll { $0.id == debt.id }
        all.insert(debt, at: 0)
        try save(all, key: .debts)
        await recordNetWorthSnapshot()
    }

    func fetchDebts() async throws -> [Debt] {
        try load([Debt].self, key: .debts)
    }

    func deleteDebt(_ debt: Debt) async throws {
        var all = try load([Debt].self, key: .debts)
        all.removeAll { $0.id == debt.id }
        try save(all, key: .debts)
        await recordNetWorthSnapshot()
    }

    // MARK: - Merchant memory (title → category, learned from saved expenses)

    static func normalizedMerchant(_ title: String) -> String {
        title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func rememberMerchant(_ title: String, categoryID: String) {
        let key = Self.normalizedMerchant(title)
        guard !key.isEmpty else { return }
        var map = (try? store.load([String: String].self, key: .merchantMemory)) ?? [:]
        guard map[key] != categoryID else { return }
        map[key] = categoryID
        try? store.save(map, key: .merchantMemory)
    }

    func categoryForMerchant(_ title: String) -> String? {
        let map = (try? store.load([String: String].self, key: .merchantMemory)) ?? [:]
        return map[Self.normalizedMerchant(title)]
    }

    // MARK: - Net worth history

    func fetchNetWorthHistory() async throws -> [NetWorthSnapshot] {
        try load([NetWorthSnapshot].self, key: .netWorthHistory)
    }

    /// Recomputes net worth from stored investments + debts and records one snapshot
    /// per day (the day's latest value wins). Called after any investment/debt change
    /// and on dashboard load, so history accrues at least daily.
    func recordNetWorthSnapshot() async {
        let inv = (try? load([Investment].self, key: .investments)) ?? []
        let deb = (try? load([Debt].self, key: .debts)) ?? []
        let invTotal = inv.reduce(0) { $0 + $1.currentValue }
        let debTotal = deb.reduce(0) { $0 + $1.currentBalance }
        guard invTotal != 0 || debTotal != 0 else { return }
        var history = (try? load([NetWorthSnapshot].self, key: .netWorthHistory)) ?? []
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        history.removeAll { cal.startOfDay(for: $0.date) == today }
        history.append(NetWorthSnapshot(date: Date(), investments: invTotal,
                                        debts: debTotal, netWorth: invTotal - debTotal))
        history.sort { $0.date < $1.date }
        try? save(history, key: .netWorthHistory)
    }

    func clearAllData() {
        store.clearAll()
        Task { await refreshWidgetSnapshot() }
    }

    // MARK: - Widget snapshot (written to the App Group for the widget extension)

    static let appGroupID = "group.com.nachi.personalfinance"

    /// Recomputes the widget data file and reloads all widget timelines.
    /// No-op until the App Group is configured on the Mac (containerURL is nil).
    func refreshWidgetSnapshot() async {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupID) else { return }

        let expenses    = (try? load([Expense].self, key: .expenses)) ?? []
        let budgets     = (try? load([Budget].self, key: .budgets)) ?? []
        let recurring   = (try? load([RecurringExpense].self, key: .recurring)) ?? []
        let userCats    = (try? load([ExpenseCategory].self, key: .categories)) ?? []
        let investments = (try? load([Investment].self, key: .investments)) ?? []
        let debts       = (try? load([Debt].self, key: .debts)) ?? []
        let history     = (try? load([NetWorthSnapshot].self, key: .netWorthHistory)) ?? []

        let cal = Calendar.current
        let now = Date()
        let m = cal.component(.month, from: now), y = cal.component(.year, from: now)

        let monthExpenses = expenses.filter {
            cal.component(.month, from: $0.date) == m && cal.component(.year, from: $0.date) == y
        }
        let monthSpent = monthExpenses.reduce(0) { $0 + $1.amount }
        let biggest = monthExpenses.max { $0.amount < $1.amount }

        let builtInIDs = Set(ExpenseCategory.prebuilt.map(\.id))
        let categories = ExpenseCategory.prebuilt + userCats.filter { !builtInIDs.contains($0.id) }
        func catName(_ id: String) -> String { categories.first { $0.id == id }?.name ?? "Other" }

        let current = budgets.filter { $0.month == m && $0.year == y }
        let stats = current.map { b -> WidgetSnapshot.BudgetStat in
            let spent = monthExpenses.filter { $0.categoryID == b.categoryID }.reduce(0) { $0 + $1.amount }
            return WidgetSnapshot.BudgetStat(name: catName(b.categoryID), spent: spent, limit: b.limitAmount)
        }
        let topBudgets = stats.sorted {
            ($0.limit > 0 ? $0.spent / $0.limit : 0) > ($1.limit > 0 ? $1.spent / $1.limit : 0)
        }

        let upcoming = recurring
            .filter { $0.isActive && $0.nextDueDate >= cal.startOfDay(for: now) }
            .sorted { $0.nextDueDate < $1.nextDueDate }
        let weekEnd = cal.date(byAdding: .day, value: 7, to: now) ?? now
        let thisWeek = upcoming.filter { $0.nextDueDate <= weekEnd }

        let invTotal = investments.reduce(0) { $0 + $1.currentValue }
        let debTotal = debts.reduce(0) { $0 + $1.currentBalance }
        let historyValues = history.suffix(30).map(\.netWorth)
        var delta: Double? = nil
        if let first = historyValues.first, first != 0, let last = historyValues.last {
            delta = (last - first) / abs(first) * 100
        }

        let snap = WidgetSnapshot(
            date: now,
            currencyCode: UserDefaults.standard.string(forKey: "defaultCurrencyCode") ?? "USD",
            maskAmounts: UserDefaults.standard.bool(forKey: "widgetMaskAmounts"),
            netWorth: invTotal - debTotal,
            netWorthDeltaPercent: delta,
            history: historyValues,
            monthSpent: monthSpent,
            monthBudget: current.reduce(0) { $0 + $1.limitAmount },
            budgets: Array(topBudgets.prefix(3)),
            budgetsOnTrack: stats.filter { $0.spent <= $0.limit }.count,
            budgetsTotal: stats.count,
            bills: upcoming.prefix(3).map {
                WidgetSnapshot.Bill(title: $0.title, amount: $0.amount, date: $0.nextDueDate)
            },
            billsThisWeekCount: thisWeek.count,
            billsThisWeekTotal: thisWeek.reduce(0) { $0 + $1.amount },
            biggestExpenseTitle: biggest?.title,
            biggestExpenseAmount: biggest?.amount
        )

        let url = container.appendingPathComponent("widget_snapshot.json")
        if let data = try? JSONEncoder().encode(snap) {
            try? data.write(to: url, options: .atomic)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private func load<T: Decodable>(_ type: T.Type, key: LocalJSONStore.Key) throws -> T {
        return try store.load(type, key: key)
    }

    private func save<T: Encodable>(_ value: T, key: LocalJSONStore.Key) throws {
        do {
            try store.save(value, key: key)
            // Every mutation funnels through here — keep the widgets current.
            Task { await refreshWidgetSnapshot() }
        } catch {
            throw CloudKitError.saveFailed(error)
        }
    }
}

// MARK: - Storage location keys (nonisolated)

enum StorageKeys {
    static let location = "storage.location"     // "unset" | "local" | "folder"
    static let bookmark = "storage.folderBookmark"
    static let path     = "storage.folderPath"
}

// MARK: - Storage manager (first-boot choice + folder bookmark)

@MainActor
final class StorageManager: ObservableObject {
    static let shared = StorageManager()

    enum Location: String { case unset, local, folder }

    @Published private(set) var location: Location
    @Published private(set) var folderName: String

    var hasChosen: Bool { location != .unset }

    private init() {
        let raw = UserDefaults.standard.string(forKey: StorageKeys.location) ?? "unset"
        location = Location(rawValue: raw) ?? .unset
        if let p = UserDefaults.standard.string(forKey: StorageKeys.path) {
            folderName = URL(fileURLWithPath: p).lastPathComponent
        } else {
            folderName = ""
        }
    }

    func chooseLocal() {
        let snapshot = LocalJSONStore.shared.snapshotRawData()   // read from current location
        UserDefaults.standard.set(Location.local.rawValue, forKey: StorageKeys.location)
        UserDefaults.standard.removeObject(forKey: StorageKeys.bookmark)
        UserDefaults.standard.removeObject(forKey: StorageKeys.path)
        folderName = ""
        location = .local
        LocalJSONStore.shared.writeRawData(snapshot)             // migrate into local
    }

    func chooseFolder(_ url: URL) throws {
        let snapshot = LocalJSONStore.shared.snapshotRawData()   // read from current location
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        #if os(macOS)
        let bm = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        #else
        let bm = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        #endif
        UserDefaults.standard.set(bm, forKey: StorageKeys.bookmark)
        UserDefaults.standard.set(url.path, forKey: StorageKeys.path)
        UserDefaults.standard.set(Location.folder.rawValue, forKey: StorageKeys.location)
        folderName = url.lastPathComponent
        location = .folder
        LocalJSONStore.shared.writeRawData(snapshot)             // migrate into the chosen folder
    }

    var locationDescription: String {
        switch location {
        case .unset:  return "Not set"
        case .local:  return "On this device"
        case .folder: return "iCloud Drive · \(folderName)"
        }
    }
}

// MARK: - Local JSON Store (writes to the chosen location)

final class LocalJSONStore {
    static let shared = LocalJSONStore()

    enum Key: String {
        case expenses    = "expenses.json"
        case recurring   = "recurring.json"
        case budgets     = "budgets.json"
        case categories  = "user_categories.json"
        case investments = "investments.json"
        case debts       = "debts.json"
        case netWorthHistory = "networth_history.json"
        case merchantMemory  = "merchant_memory.json"
    }

    private init() {}

    func save<T: Encodable>(_ value: T, key: Key) throws {
        try withDirectory { dir in
            let url = dir.appendingPathComponent(key.rawValue)
            let data = try JSONEncoder().encode(value)
            try data.write(to: url, options: .atomic)
        }
    }

    func load<T: Decodable>(_ type: T.Type, key: Key) throws -> T {
        try withDirectory { dir in
            let url = dir.appendingPathComponent(key.rawValue)
            guard FileManager.default.fileExists(atPath: url.path) else {
                return try JSONDecoder().decode(type, from: Data("[]".utf8))
            }
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(type, from: data)
        }
    }

    // Raw snapshot / restore — used to migrate data between storage locations.

    func snapshotRawData() -> [Key: Data] {
        var out: [Key: Data] = [:]
        for key in [Key.expenses, .recurring, .budgets, .categories, .investments, .debts, .netWorthHistory, .merchantMemory] {
            if let bytes = try? readRaw(key) { out[key] = bytes }
        }
        return out
    }

    func writeRawData(_ snapshot: [Key: Data]) {
        for (key, data) in snapshot { try? writeRaw(key, data) }
    }

    private func readRaw(_ key: Key) throws -> Data? {
        try withDirectory { dir in
            let url = dir.appendingPathComponent(key.rawValue)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return try Data(contentsOf: url)
        }
    }

    private func writeRaw(_ key: Key, _ data: Data) throws {
        try withDirectory { dir in
            let url = dir.appendingPathComponent(key.rawValue)
            try data.write(to: url, options: .atomic)
        }
    }

    func clearAll() {
        for key in [Key.expenses, .recurring, .budgets, .categories, .investments, .debts, .netWorthHistory, .merchantMemory] {
            try? withDirectory { dir in
                let url = dir.appendingPathComponent(key.rawValue)
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
            }
        }
    }

    /// Resolves the active storage directory, handling security-scoped folder access.
    private func withDirectory<T>(_ body: (URL) throws -> T) throws -> T {
        let loc = UserDefaults.standard.string(forKey: StorageKeys.location) ?? "local"
        if loc == "folder", let bm = UserDefaults.standard.data(forKey: StorageKeys.bookmark) {
            var stale = false
            #if os(macOS)
            let folder = try? URL(resolvingBookmarkData: bm, options: .withSecurityScope,
                                  relativeTo: nil, bookmarkDataIsStale: &stale)
            #else
            let folder = try? URL(resolvingBookmarkData: bm, options: [],
                                  relativeTo: nil, bookmarkDataIsStale: &stale)
            #endif
            if let folder {
                let scoped = folder.startAccessingSecurityScopedResource()
                defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
                let dir = folder.appendingPathComponent("PersonalFinanceData", isDirectory: true)
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                return try body(dir)
            }
        }
        return try body(localDirectory())
    }

    private func localDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("PersonalFinance", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
