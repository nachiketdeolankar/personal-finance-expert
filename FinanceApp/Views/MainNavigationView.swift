import SwiftUI
import Combine

struct MainNavigationView: View {
    @EnvironmentObject var vm: ExpenseViewModel
    @ObservedObject private var router = NavigationRouter.shared
    @State private var selected: NavItem = .dashboard
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var isCompact: Bool { sizeClass == .compact }
    #else
    private let isCompact = false
    #endif

    var body: some View {
        // System Liquid Glass tab bar on iPhone; adapts to a sidebar on iPad and Mac.
        TabView(selection: $selected) {
            tab(.dashboard)
            tab(.expenses)
            tab(.investments)
            tab(.debt)
            // Sidebar-only on iPad / Mac (on iPhone it would push Search into "More").
            // On iPhone these are reached from the Overview toolbar (Settings) and the
            // Expenses toolbar (Recurring, Categories).
            if !isCompact {
                TabSection("Manage") {
                    tab(.recurring)
                    tab(.categories)
                    tab(.settings)
                }
                .defaultVisibility(.hidden, for: .tabBar)
            }
            Tab(NavItem.search.title, systemImage: NavItem.search.icon, value: .search, role: .search) {
                NavigationStack { screen(for: .search) }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        #if os(iOS)
        .tabBarMinimizeBehavior(.onScrollDown)
        #endif
        #if os(macOS)
        .frame(minWidth: 820, minHeight: 620)
        #endif
        .task { await vm.loadAll() }
        // Deep-link target set by OpenSectionIntent (Siri / Shortcuts).
        .onReceive(router.$pending) { item in
            guard let item else { return }
            withAnimation(.snappy(duration: 0.2)) { selected = item }
            router.pending = nil
        }
        // Widget taps (widgetURL) arrive here as pfe:// URLs.
        .onOpenURL { url in
            switch url.host {
            case "add":       selected = .expenses; router.showAddExpense = true
            case "overview":  selected = .dashboard
            case "expenses":  selected = .expenses
            case "recurring": selected = .recurring
            default: break
            }
        }
        .sheet(isPresented: $router.showAddExpense) { AddExpenseView() }
    }

    private func tab(_ item: NavItem) -> some TabContent<NavItem> {
        Tab(item.title, systemImage: item.icon, value: item) {
            NavigationStack { screen(for: item) }
        }
    }

    @ViewBuilder
    private func screen(for item: NavItem) -> some View {
        switch item {
        case .dashboard:   DashboardView()
        case .expenses:    ExpenseListView()
        case .investments: InvestmentsView()
        case .debt:        DebtsView()
        case .recurring:   RecurringExpenseListView()
        case .categories:  CategoryManagerView()
        case .search:      GlobalSearchView()
        case .settings:    SettingsView()
        }
    }
}

enum NavItem: String, CaseIterable {
    case dashboard, expenses, investments, debt, recurring, categories, search, settings

    var title: String {
        switch self {
        case .dashboard:   return "Overview"
        case .expenses:    return "Expenses"
        case .investments: return "Investments"
        case .debt:        return "Debt"
        case .recurring:   return "Recurring"
        case .categories:  return "Categories"
        case .search:      return "Search"
        case .settings:    return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .dashboard:   return "square.grid.2x2.fill"
        case .expenses:    return "creditcard.fill"
        case .investments: return "chart.line.uptrend.xyaxis"
        case .debt:        return "creditcard.trianglebadge.exclamationmark"
        case .recurring:   return "repeat"
        case .categories:  return "tag.fill"
        case .search:      return "magnifyingglass"
        case .settings:    return "gearshape.fill"
        }
    }
}

// MARK: - Cross-section search

struct GlobalSearchView: View {
    @EnvironmentObject var vm: ExpenseViewModel
    @State private var query = ""
    @State private var investments: [Investment] = []
    @State private var debts: [Debt] = []

    var body: some View {
        List {
            if query.isEmpty {
                Text("Search across expenses, recurring, investments and debts.")
                    .font(.caption).foregroundStyle(Theme.textTertiary)
                    .listRowBackground(Color.clear)
            } else if matchedExpenses.isEmpty && matchedRecurring.isEmpty
                        && matchedInvestments.isEmpty && matchedDebts.isEmpty {
                Text("No matches for “\(query)”.")
                    .font(.subheadline).foregroundStyle(Theme.textSecondary)
                    .listRowBackground(Color.clear)
            } else {
                if !matchedExpenses.isEmpty {
                    Section("Expenses") {
                        ForEach(matchedExpenses) { e in
                            ExpenseRow(expense: e, category: vm.category(for: e.categoryID))
                                .listRowBackground(Theme.card)
                        }
                    }
                }
                if !matchedRecurring.isEmpty {
                    Section("Recurring") {
                        ForEach(matchedRecurring) { r in
                            RecurringExpenseRow(recurring: r, category: vm.category(for: r.categoryID))
                                .listRowBackground(Theme.card)
                        }
                    }
                }
                if !matchedInvestments.isEmpty {
                    Section("Investments") {
                        ForEach(matchedInvestments) { inv in
                            HStack {
                                Image(systemName: inv.type.icon).foregroundStyle(inv.color)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(inv.name).font(.subheadline.weight(.medium))
                                    Text(inv.symbol.isEmpty ? inv.type.rawValue : inv.symbol)
                                        .font(.caption).foregroundStyle(Theme.textTertiary)
                                }
                                Spacer()
                                Text(inv.currentValue.currencyWhole)
                                    .font(.subheadline.weight(.bold))
                            }
                            .listRowBackground(Theme.card)
                        }
                    }
                }
                if !matchedDebts.isEmpty {
                    Section("Debts") {
                        ForEach(matchedDebts) { d in
                            HStack {
                                Image(systemName: d.type.icon).foregroundStyle(d.color)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(d.name).font(.subheadline.weight(.medium))
                                    Text(d.type.rawValue).font(.caption).foregroundStyle(Theme.textTertiary)
                                }
                                Spacer()
                                Text(d.currentBalance.currencyWhole)
                                    .font(.subheadline.weight(.bold))
                            }
                            .listRowBackground(Theme.card)
                        }
                    }
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Search")
        .searchable(text: $query, prompt: "Search everything")
        .task {
            investments = (try? await CloudKitManager.shared.fetchInvestments()) ?? []
            debts = (try? await CloudKitManager.shared.fetchDebts()) ?? []
        }
    }

    private func matches(_ text: String...) -> Bool {
        text.contains { $0.localizedCaseInsensitiveContains(query) }
    }

    private var matchedExpenses: [Expense] {
        vm.expenses.filter { matches($0.title, $0.notes, vm.category(for: $0.categoryID).name) }
    }
    private var matchedRecurring: [RecurringExpense] {
        vm.recurringExpenses.filter { matches($0.title, $0.notes) }
    }
    private var matchedInvestments: [Investment] {
        investments.filter { matches($0.name, $0.symbol, $0.notes, $0.type.rawValue) }
    }
    private var matchedDebts: [Debt] {
        debts.filter { matches($0.name, $0.notes, $0.type.rawValue) }
    }
}
