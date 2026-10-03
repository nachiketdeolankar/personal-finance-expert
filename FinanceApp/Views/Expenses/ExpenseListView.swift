import SwiftUI

struct ExpenseListView: View {
    @EnvironmentObject var vm: ExpenseViewModel
    @State private var showAddExpense: Bool = false
    @State private var selectedExpense: Expense?
    @State private var searchText: String = ""
    @State private var selectedCategoryFilter: String = "all"
    @State private var sortOrder: SortOrder = .dateDesc
    @ObservedObject private var router = NavigationRouter.shared

    enum SortOrder: String, CaseIterable {
        case dateDesc  = "Newest First"
        case dateAsc   = "Oldest First"
        case amountDesc = "Highest Amount"
        case amountAsc  = "Lowest Amount"
    }

    var filtered: [Expense] {
        var list = vm.expenses
        if !searchText.isEmpty {
            list = list.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.notes.localizedCaseInsensitiveContains(searchText)
            }
        }
        if selectedCategoryFilter != "all" {
            list = list.filter { $0.categoryID == selectedCategoryFilter }
        }
        switch sortOrder {
        case .dateDesc:   return list.sorted { $0.date > $1.date }
        case .dateAsc:    return list.sorted { $0.date < $1.date }
        case .amountDesc: return list.sorted { $0.amount > $1.amount }
        case .amountAsc:  return list.sorted { $0.amount < $1.amount }
        }
    }

    var grouped: [(key: String, expenses: [Expense])] {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        let groups = Dictionary(grouping: filtered) { expense in
            formatter.string(from: expense.date)
        }
        return groups.map { (key: $0.key, expenses: $0.value) }
            .sorted { lhs, rhs in
                lhs.expenses[0].date > rhs.expenses[0].date
            }
    }

    var body: some View {
        Group {
            if vm.isLoading {
                ProgressView("Loading expenses…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.expenses.isEmpty {
                emptyState
            } else {
                List {
                    categoryFilterRow

                    ForEach(grouped, id: \.key) { group in
                        Section(header: groupHeader(group.key, expenses: group.expenses)) {
                            ForEach(group.expenses) { expense in
                                ExpenseRow(expense: expense, category: vm.category(for: expense.categoryID))
                                    .listRowBackground(Theme.card)
                                    .contentShape(Rectangle())
                                    .onTapGesture { selectedExpense = expense }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button(role: .destructive) {
                                            Task { await vm.deleteExpense(expense) }
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                        Button {
                                            selectedExpense = expense
                                        } label: {
                                            Label("Edit", systemImage: "pencil")
                                        }
                                        .tint(.blue)
                                    }
                            }
                        }
                    }
                }
                #if os(iOS)
                .listStyle(.insetGrouped)
                #endif
                .scrollContentBackground(.hidden)
            }
        }
        .background(Theme.background)
        .navigationTitle("Expenses")
        .searchable(text: $searchText, prompt: "Search expenses")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu("More", systemImage: "ellipsis") {
                    Picker("Sort", systemImage: "arrow.up.arrow.down", selection: $sortOrder) {
                        ForEach(SortOrder.allCases, id: \.self) { order in
                            Text(order.rawValue).tag(order)
                        }
                    }
                    .pickerStyle(.menu)
                    Section {
                        Button("Recurring", systemImage: "repeat") { router.showRecurring = true }
                        Button("Categories", systemImage: "tag") { router.showCategories = true }
                    }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Add Expense", systemImage: "plus") {
                    selectedExpense = nil
                    showAddExpense = true
                }
            }
        }
        .navigationDestination(isPresented: $router.showRecurring) { RecurringExpenseListView() }
        .navigationDestination(isPresented: $router.showCategories) { CategoryManagerView() }
        .sheet(isPresented: $showAddExpense) {
            AddExpenseView()
        }
        .sheet(item: $selectedExpense) { expense in
            AddExpenseView(editingExpense: expense)
        }
        .task { await vm.loadAll() }
        .refreshable { await vm.loadAll() }
    }

    // MARK: - Category filter chips

    private var categoryFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(id: "all", name: "All", icon: "square.grid.2x2")
                ForEach(vm.categories) { cat in
                    filterChip(id: cat.id, name: cat.name, icon: cat.iconName, color: cat.color)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func filterChip(id: String, name: String, icon: String, color: Color = .secondary) -> some View {
        Button {
            selectedCategoryFilter = id
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.caption2)
                Text(name).font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                selectedCategoryFilter == id
                    ? (id == "all" ? Theme.accent : color).opacity(0.15)
                    : Theme.fill
                , in: Capsule()
            )
            .foregroundStyle(selectedCategoryFilter == id ? (id == "all" ? Theme.accent : color) : .secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Group Header

    private func groupHeader(_ title: String, expenses: [Expense]) -> some View {
        HStack {
            Text(title).font(.subheadline).fontWeight(.semibold)
            Spacer()
            Text(expenses.reduce(0) { $0 + $1.amount }.currencyFormatted)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Expenses Yet", systemImage: "tray")
        } description: {
            Text("Tap + to add your first expense.")
        } actions: {
            Button("Add Expense") { showAddExpense = true }
                .buttonStyle(.glassProminent)
        }
    }
}

// MARK: - Expense Row

struct ExpenseRow: View {
    let expense: Expense
    let category: ExpenseCategory

    var body: some View {
        HStack(spacing: 12) {
            CategoryIconView(category: category, size: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text(expense.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                HStack(spacing: 6) {
                    Text(expense.date, format: .dateTime.month(.abbreviated).day())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if expense.isRecurring {
                        Image(systemName: "repeat")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if expense.receiptAssetData != nil {
                        Image(systemName: "paperclip")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(expense.formattedAmount)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(category.name)
                    .font(.caption2)
                    .foregroundStyle(category.color)
            }
        }
        .padding(.vertical, 4)
    }
}
