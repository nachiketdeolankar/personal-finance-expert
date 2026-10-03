import SwiftUI
import Charts

enum DashPeriod: String, CaseIterable, Identifiable {
    case week = "Week", month = "Month", year = "Year"
    var id: String { rawValue }
}

struct DashboardView: View {
    @EnvironmentObject var vm: ExpenseViewModel
    @State private var period: DashPeriod = .month
    @State private var investmentsTotal: Double = 0
    @State private var debtsTotal: Double = 0
    @State private var netWorthHistory: [NetWorthSnapshot] = []
    @State private var showBudgetEditor = false
    @ObservedObject private var router = NavigationRouter.shared

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.spacing) {
                heroCard
                if investmentsTotal > 0 || debtsTotal > 0 { netWorthCard }
                if let recap = monthRecap { recapCard(recap) }
                periodPicker
                if !categoryShares.isEmpty { categoryCard }
                recentCard
                budgetCard
            }
            .padding(Theme.spacing)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
        .navigationTitle("Overview")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                NavigationLink { SettingsView() } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Add Expense", systemImage: "plus") {
                    NavigationRouter.shared.showAddExpense = true
                }
            }
        }
        .navigationDestination(isPresented: $router.showSettings) { SettingsView() }
        .sheet(isPresented: $showBudgetEditor) { BudgetEditorView() }
        .task {
            let inv = (try? await CloudKitManager.shared.fetchInvestments()) ?? []
            let deb = (try? await CloudKitManager.shared.fetchDebts()) ?? []
            investmentsTotal = inv.reduce(0) { $0 + $1.currentValue }
            debtsTotal = deb.reduce(0) { $0 + $1.currentBalance }
            await CloudKitManager.shared.recordNetWorthSnapshot()
            netWorthHistory = (try? await CloudKitManager.shared.fetchNetWorthHistory()) ?? []
        }
    }

    // MARK: - Hero

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TOTAL SPENT")
                .monoLabel()
            Text(periodTotal.currencyWhole)
                .font(Theme.figure(44))
                .foregroundStyle(Theme.textPrimary)
            if let pct = trendPercent {
                HStack(spacing: 4) {
                    Image(systemName: pct >= 0 ? "arrow.up" : "arrow.down")
                    Text("\(abs(pct), specifier: "%.1f")% vs last \(period.rawValue.lowercased())")
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(pct >= 0 ? Theme.upTrend : Theme.downTrend)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background((pct >= 0 ? Theme.upTrend : Theme.downTrend).opacity(0.14), in: Capsule())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .glassCard()
    }

    // MARK: - Net worth

    private var netWorthCard: some View {
        let net = investmentsTotal - debtsTotal
        return ThemedCard(title: "Net Worth") {
            VStack(alignment: .leading, spacing: 14) {
                Text(net.currencyWhole)
                    .font(Theme.figure(34))
                    .foregroundStyle(net >= 0 ? Theme.textPrimary : Theme.danger)
                if netWorthHistory.count > 1 { netWorthChart }
                HStack(spacing: 12) {
                    miniStat("Investments", investmentsTotal.currencyWhole, "chart.line.uptrend.xyaxis")
                    miniStat("Debt", debtsTotal.currencyWhole, "creditcard.trianglebadge.exclamationmark")
                }
            }
        }
    }

    // Monochrome history line — accent only, per Direction C.
    private var netWorthChart: some View {
        Chart(netWorthHistory) { snap in
            AreaMark(x: .value("Date", snap.date), y: .value("Net Worth", snap.netWorth))
                .foregroundStyle(LinearGradient(colors: [Theme.accent.opacity(0.16), .clear],
                                                startPoint: .top, endPoint: .bottom))
            LineMark(x: .value("Date", snap.date), y: .value("Net Worth", snap.netWorth))
                .foregroundStyle(Theme.accent)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) {
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .font(Theme.label(8))
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) {
                AxisGridLine().foregroundStyle(Theme.divider)
                AxisValueLabel().font(Theme.label(8))
            }
        }
        .frame(height: 90)
    }

    private func miniStat(_ label: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.caption2).foregroundStyle(Theme.accent)
                Text(label.uppercased()).monoLabel(9)
            }
            Text(value).font(.subheadline.weight(.bold)).foregroundStyle(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .glassCard(Theme.radiusSmall)
    }

    // MARK: - Month recap

    private struct MonthRecap {
        let monthName: String
        let spent: Double
        let deltaPercent: Double?
        let topCategory: (name: String, amount: Double)?
        let biggestExpense: (title: String, amount: Double)?
        let budgetsOver: Int
        let budgetsTotal: Int
    }

    private var monthRecap: MonthRecap? {
        let cal = Calendar.current
        let now = Date()
        let m = cal.component(.month, from: now), y = cal.component(.year, from: now)
        let thisMonth = vm.expenses(for: m, year: y)
        guard !thisMonth.isEmpty else { return nil }
        let spent = thisMonth.reduce(0) { $0 + $1.amount }

        var delta: Double? = nil
        if let prev = cal.date(byAdding: .month, value: -1, to: now) {
            let last = vm.expenses(for: cal.component(.month, from: prev),
                                   year: cal.component(.year, from: prev))
                .reduce(0) { $0 + $1.amount }
            if last > 0 { delta = (spent - last) / last * 100 }
        }

        var byCat: [String: Double] = [:]
        for e in thisMonth { byCat[e.categoryID, default: 0] += e.amount }
        let top = byCat.max { $0.value < $1.value }
            .map { (name: vm.category(for: $0.key).name, amount: $0.value) }
        let biggest = thisMonth.max { $0.amount < $1.amount }
            .map { (title: $0.title, amount: $0.amount) }

        let current = vm.budgets.filter { $0.month == m && $0.year == y }
        let over = current.filter { vm.totalSpent(for: $0.categoryID, month: m, year: y) > $0.limitAmount }

        return MonthRecap(monthName: now.formatted(.dateTime.month(.wide)),
                          spent: spent, deltaPercent: delta,
                          topCategory: top, biggestExpense: biggest,
                          budgetsOver: over.count, budgetsTotal: current.count)
    }

    private func recapCard(_ recap: MonthRecap) -> some View {
        ThemedCard(title: "\(recap.monthName) Recap") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(recap.spent.currencyWhole)
                        .font(Theme.figure(26))
                        .foregroundStyle(Theme.textPrimary)
                    if let d = recap.deltaPercent {
                        Text("\(d >= 0 ? "▲" : "▼") \(abs(d), specifier: "%.0f")% vs last month")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(d >= 0 ? Theme.upTrend : Theme.downTrend)
                    }
                }
                VStack(spacing: 8) {
                    if let top = recap.topCategory {
                        recapRow("Top category", "\(top.name) · \(top.amount.currencyWhole)")
                    }
                    if let big = recap.biggestExpense {
                        recapRow("Biggest expense", "\(big.title) · \(big.amount.currencyWhole)")
                    }
                    if recap.budgetsTotal > 0 {
                        recapRow("Budgets", recap.budgetsOver == 0
                                 ? "All \(recap.budgetsTotal) on track"
                                 : "\(recap.budgetsOver) of \(recap.budgetsTotal) over limit")
                    }
                }
            }
        }
    }

    private func recapRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label.uppercased()).monoLabel(9)
            Spacer()
            Text(value)
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.trailing)
        }
    }

    // MARK: - Period picker

    private var periodPicker: some View {
        Picker("Period", selection: $period.animation(.snappy(duration: 0.2))) {
            ForEach(DashPeriod.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    // MARK: - Recent

    private var recentCard: some View {
        let recent = Array(vm.expenses.sorted { $0.date > $1.date }.prefix(5))
        return ThemedCard(title: "Recent") {
            if recent.isEmpty {
                Text("No expenses yet")
                    .font(.caption).foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity).padding(.vertical, 24)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(recent.enumerated()), id: \.element.id) { idx, exp in
                        let cat = vm.category(for: exp.categoryID)
                        HStack(spacing: 12) {
                            CategoryIconView(category: cat, size: 34)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(exp.title)
                                    .font(.subheadline.weight(.medium)).foregroundStyle(Theme.textPrimary)
                                Text(recentSubtitle(exp))
                                    .font(.caption).foregroundStyle(Theme.textTertiary)
                            }
                            Spacer()
                            Text(exp.formattedAmount)
                                .font(.subheadline.weight(.bold)).foregroundStyle(Theme.textPrimary)
                        }
                        .padding(.vertical, 8)
                        if idx < recent.count - 1 {
                            Rectangle().fill(Theme.divider).frame(height: 0.5).padding(.leading, 46)
                        }
                    }
                }
            }
        }
    }

    private func recentSubtitle(_ e: Expense) -> String {
        let d = e.date.formatted(.dateTime.month(.abbreviated).day())
        if let pm = e.paymentMethod, !pm.isEmpty { return "\(d) · \(pm)" }
        return d
    }

    // MARK: - By Category

    private var categoryCard: some View {
        ThemedCard(title: "By Category") {
            HStack(alignment: .center, spacing: 20) {
                ZStack {
                    Chart(categoryShares, id: \.category.id) { item in
                        SectorMark(angle: .value("amt", item.amount),
                                   innerRadius: .ratio(0.66), angularInset: 2)
                            .foregroundStyle(item.category.color)
                            .cornerRadius(3)
                    }
                    .chartLegend(.hidden)
                    .frame(width: 120, height: 120)
                    VStack(spacing: 0) {
                        Text("\(categoryShares.count)")
                            .font(.title2.weight(.bold)).foregroundStyle(Theme.textPrimary)
                        Text("categories").font(.system(size: 9)).foregroundStyle(Theme.textTertiary)
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(categoryShares.prefix(5), id: \.category.id) { item in
                        HStack(spacing: 8) {
                            Circle().fill(item.category.color).frame(width: 9, height: 9)
                            Text(item.category.name).font(.caption).foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                            Spacer()
                            Text("\(Int(item.share * 100))%")
                                .font(.caption.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Budgets

    private var budgetCard: some View {
        let cal = Calendar.current
        let m = cal.component(.month, from: Date()), y = cal.component(.year, from: Date())
        let current = vm.budgets.filter { $0.month == m && $0.year == y }
        return ThemedCard(title: "Budgets") {
            if current.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("No budgets set this month.")
                        .font(.caption).foregroundStyle(Theme.textTertiary)
                    Button("Set Budgets…") { showBudgetEditor = true }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
            } else {
                VStack(spacing: 14) {
                    HStack {
                        Spacer()
                        Button("Edit…") { showBudgetEditor = true }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                            .buttonStyle(.plain)
                    }
                    ForEach(current) { budget in
                        let cat = vm.category(for: budget.categoryID)
                        let spent = vm.totalSpent(for: budget.categoryID, month: m, year: y)
                        let progress = budget.limitAmount > 0 ? min(spent / budget.limitAmount, 1) : 0
                        let over = spent > budget.limitAmount
                        VStack(spacing: 7) {
                            HStack {
                                Text(cat.name).font(.subheadline).foregroundStyle(Theme.textPrimary)
                                Spacer()
                                Text("\(spent.currencyWhole) / \(budget.limitAmount.currencyWhole)")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(over ? Theme.danger : Theme.textTertiary)
                            }
                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Theme.track)
                                    Capsule().fill(over ? Theme.danger : Theme.accent)
                                        .frame(width: max(6, g.size.width * progress))
                                }
                            }
                            .frame(height: 7)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Data

    private var periodRange: (start: Date, end: Date) {
        let cal = Calendar.current
        let now = Date()
        switch period {
        case .week:
            let start = cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: now))!
            return (start, now)
        case .month:
            let comps = cal.dateComponents([.year, .month], from: now)
            let start = cal.date(from: comps)!
            return (start, now)
        case .year:
            let comps = cal.dateComponents([.year], from: now)
            let start = cal.date(from: comps)!
            return (start, now)
        }
    }

    private func total(in start: Date, _ end: Date) -> Double {
        vm.expenses.filter { $0.date >= start && $0.date <= end }.reduce(0) { $0 + $1.amount }
    }

    private var periodTotal: Double { total(in: periodRange.start, periodRange.end) }

    private var trendPercent: Double? {
        let cal = Calendar.current
        let (start, end) = periodRange
        let span: Int
        let comp: Calendar.Component
        switch period {
        case .week:  span = 7;  comp = .day
        case .month: span = 1;  comp = .month
        case .year:  span = 1;  comp = .year
        }
        guard let prevStart = cal.date(byAdding: comp, value: -span, to: start),
              let prevEnd = cal.date(byAdding: comp, value: -span, to: end) else { return nil }
        let prev = total(in: prevStart, prevEnd)
        guard prev > 0 else { return nil }
        return (periodTotal - prev) / prev * 100
    }

    private var categoryShares: [(category: ExpenseCategory, amount: Double, share: Double)] {
        let (start, end) = periodRange
        let inPeriod = vm.expenses.filter { $0.date >= start && $0.date <= end }
        let grandTotal = inPeriod.reduce(0) { $0 + $1.amount }
        guard grandTotal > 0 else { return [] }
        var byCat: [String: Double] = [:]
        for e in inPeriod { byCat[e.categoryID, default: 0] += e.amount }
        return byCat.map { (category: vm.category(for: $0.key), amount: $0.value, share: $0.value / grandTotal) }
            .sorted { $0.amount > $1.amount }
    }
}

// MARK: - Formatting helpers

extension Double {
    var currencyFormatted: String {
        let f = NumberFormatter(); f.numberStyle = .currency; f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: self)) ?? "$\(self)"
    }
    var currencyWhole: String {
        let f = NumberFormatter(); f.numberStyle = .currency; f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: self)) ?? "$\(Int(self))"
    }
    var shortFormatted: String {
        if self >= 1_000 { return String(format: "%.1fk", self / 1_000) }
        return String(format: "%.0f", self)
    }
}

// MARK: - Budget editor (with smart suggestions)

struct BudgetEditorView: View {
    @EnvironmentObject var vm: ExpenseViewModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("defaultCurrencyCode") private var defaultCurrencyCode: String = "USD"

    /// categoryID → entered amount text. Prefilled from this month's budgets.
    @State private var amounts: [String: String] = [:]

    private var month: Int { Calendar.current.component(.month, from: Date()) }
    private var year: Int  { Calendar.current.component(.year, from: Date()) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(vm.categories) { cat in
                        budgetRow(cat)
                    }
                    .listRowBackground(Theme.card)
                } footer: {
                    Text("Suggestions are your average monthly spend over the last 3 months. Clearing a field removes that budget.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Budgets · \(Date().formatted(.dateTime.month(.wide)))")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(role: .close) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) { save() }
                }
            }
            .onAppear {
                for b in vm.budgets where b.month == month && b.year == year {
                    amounts[b.categoryID] = b.limitAmount == 0 ? "" : String(format: "%.0f", b.limitAmount)
                }
            }
        }
    }

    private func budgetRow(_ cat: ExpenseCategory) -> some View {
        HStack(spacing: 10) {
            CategoryIconView(category: cat, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(cat.name).font(.subheadline)
                if let suggestion = vm.suggestedBudget(for: cat.id) {
                    Button("Use \(suggestion.currencyWhole) (3-mo avg)") {
                        amounts[cat.id] = String(format: "%.0f", suggestion)
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .buttonStyle(.plain)
                }
            }
            Spacer()
            TextField("None", text: Binding(
                get: { amounts[cat.id] ?? "" },
                set: { amounts[cat.id] = $0 }
            ))
            #if os(iOS)
            .keyboardType(.decimalPad)
            #endif
            .multilineTextAlignment(.trailing)
            .frame(maxWidth: 90)
        }
        .padding(.vertical, 2)
    }

    private func save() {
        Task {
            for cat in vm.categories {
                let text = amounts[cat.id]?.trimmingCharacters(in: .whitespaces) ?? ""
                let value = Double(text) ?? 0
                let existing = vm.budget(for: cat.id, month: month, year: year)
                if value > 0 {
                    if let existing, existing.limitAmount == value { continue }
                    var b = existing ?? Budget(categoryID: cat.id, limitAmount: value,
                                              currencyCode: defaultCurrencyCode,
                                              month: month, year: year)
                    b.limitAmount = value
                    await vm.saveBudget(b)
                } else if let existing {
                    await vm.deleteBudget(existing)
                }
            }
            dismiss()
        }
    }
}
