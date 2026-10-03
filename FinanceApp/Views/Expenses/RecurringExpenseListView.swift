import SwiftUI

struct RecurringExpenseListView: View {
    @EnvironmentObject var vm: ExpenseViewModel
    @State private var showAdd: Bool = false

    var body: some View {
        Group {
            if vm.recurringExpenses.isEmpty {
                ContentUnavailableView {
                    Label("No Recurring Expenses", systemImage: "repeat.circle")
                } description: {
                    Text("Track subscriptions, rent, and other recurring costs.")
                } actions: {
                    Button("Add Recurring") { showAdd = true }
                        .buttonStyle(.glassProminent)
                }
            } else {
                List {
                    ForEach(vm.recurringExpenses) { recurring in
                        RecurringExpenseRow(recurring: recurring, category: vm.category(for: recurring.categoryID))
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    Task { await vm.deleteRecurringExpense(recurring) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .listRowBackground(Theme.card)
                    }
                }
                #if os(iOS)
                .listStyle(.insetGrouped)
                #endif
                .scrollContentBackground(.hidden)
                .background(Theme.background)
            }
        }
        .navigationTitle("Recurring")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddExpenseView()
        }
    }
}

struct RecurringExpenseRow: View {
    let recurring: RecurringExpense
    let category: ExpenseCategory

    var body: some View {
        HStack(spacing: 12) {
            CategoryIconView(category: category, size: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text(recurring.title).font(.subheadline).fontWeight(.medium)
                HStack(spacing: 6) {
                    Text(recurring.frequency.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("·").foregroundStyle(.tertiary)
                    Text("Next: \(recurring.nextDueDate, format: .dateTime.month(.abbreviated).day())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(recurring.formattedAmount)
                    .font(.subheadline).fontWeight(.semibold)
                Text(recurring.isActive ? "Active" : "Paused")
                    .font(.caption2)
                    .foregroundStyle(recurring.isActive ? .green : .secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
