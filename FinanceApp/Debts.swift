import SwiftUI
import Combine

// MARK: - Model

enum DebtType: String, Codable, CaseIterable, Identifiable {
    case creditCard  = "Credit Card"
    case loan        = "Loan"
    case mortgage    = "Mortgage"
    case studentLoan = "Student Loan"
    case auto        = "Auto Loan"
    case personal    = "Personal"
    case medical     = "Medical"
    case other       = "Other"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .creditCard:  return "creditcard.fill"
        case .loan:        return "banknote.fill"
        case .mortgage:    return "house.fill"
        case .studentLoan: return "graduationcap.fill"
        case .auto:        return "car.fill"
        case .personal:    return "person.fill"
        case .medical:     return "cross.case.fill"
        case .other:       return "doc.text.fill"
        }
    }

    var colorHex: String {
        switch self {
        case .creditCard:  return "#FF6B6B"
        case .loan:        return "#6E55E0"
        case .mortgage:    return "#96CEB4"
        case .studentLoan: return "#45B7D1"
        case .auto:        return "#F8B500"
        case .personal:    return "#A29BFE"
        case .medical:     return "#FF6B9D"
        case .other:       return "#B2BEC3"
        }
    }

    var color: Color { Color(hex: colorHex) ?? Theme.accent }
}

struct Debt: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var type: DebtType
    var originalAmount: Double
    var currentBalance: Double
    var interestRate: Double      // APR %
    var minimumPayment: Double
    var currencyCode: String
    var dueDay: Int               // day of month (1-31)
    var notes: String
    var createdAt: Date
    var updatedAt: Date

    init(id: String = UUID().uuidString, name: String, type: DebtType = .creditCard,
         originalAmount: Double = 0, currentBalance: Double = 0, interestRate: Double = 0,
         minimumPayment: Double = 0, currencyCode: String = "USD", dueDay: Int = 1,
         notes: String = "") {
        self.id = id
        self.name = name
        self.type = type
        self.originalAmount = originalAmount
        self.currentBalance = currentBalance
        self.interestRate = interestRate
        self.minimumPayment = minimumPayment
        self.currencyCode = currencyCode
        self.dueDay = dueDay
        self.notes = notes
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var currency: Currency { Currency.all.first { $0.code == currencyCode } ?? .usd }
    var paidOff: Double { max(originalAmount - currentBalance, 0) }
    var progress: Double { originalAmount > 0 ? min(paidOff / originalAmount, 1) : 0 }
    var color: Color { type.color }
}

// MARK: - View Model

@MainActor
final class DebtViewModel: ObservableObject {
    @Published var debts: [Debt] = []
    @Published var isLoading = false
    @Published var error: String?

    private let ck = CloudKitManager.shared

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do { debts = try await ck.fetchDebts() }
        catch { self.error = error.localizedDescription }
    }

    func add(_ d: Debt) async {
        do { try await ck.saveDebt(d); debts.insert(d, at: 0) }
        catch { self.error = error.localizedDescription }
    }

    func update(_ d: Debt) async {
        do {
            try await ck.saveDebt(d)
            if let i = debts.firstIndex(where: { $0.id == d.id }) { debts[i] = d }
        } catch { self.error = error.localizedDescription }
    }

    func delete(_ d: Debt) async {
        do { try await ck.deleteDebt(d); debts.removeAll { $0.id == d.id } }
        catch { self.error = error.localizedDescription }
    }

    var totalBalance: Double  { debts.reduce(0) { $0 + $1.currentBalance } }
    var totalOriginal: Double { debts.reduce(0) { $0 + $1.originalAmount } }
    var totalPaidOff: Double  { max(totalOriginal - totalBalance, 0) }
    var overallProgress: Double { totalOriginal > 0 ? min(totalPaidOff / totalOriginal, 1) : 0 }
    var totalMinimum: Double   { debts.reduce(0) { $0 + $1.minimumPayment } }
    var avgAPR: Double {
        let bal = totalBalance
        guard bal > 0 else { return 0 }
        return debts.reduce(0) { $0 + $1.currentBalance * $1.interestRate } / bal
    }
}

// MARK: - Debts screen

struct DebtsView: View {
    @StateObject private var vm = DebtViewModel()
    @State private var showAdd = false
    @State private var editing: Debt?

    var body: some View {
        Group {
            if vm.debts.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: Theme.spacing) {
                        debtCard
                        statRow
                        accountsCard
                    }
                    .padding(Theme.spacing)
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .navigationTitle("Debt")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Debt", systemImage: "plus") { editing = nil; showAdd = true }
            }
        }
        .sheet(isPresented: $showAdd) { AddDebtView(vm: vm) }
        .sheet(item: $editing) { d in AddDebtView(vm: vm, editing: d) }
        .task { await vm.load() }
    }

    private var debtCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TOTAL DEBT")
                .monoLabel()
            Text(vm.totalBalance.currencyWhole)
                .font(Theme.figure(42))
                .foregroundStyle(Theme.textPrimary)
            // overall payoff progress
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("\(Int(vm.overallProgress * 100))% paid off")
                        .font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                    Spacer()
                    Text("\(vm.totalPaidOff.currencyWhole) of \(vm.totalOriginal.currencyWhole)")
                        .font(.caption).foregroundStyle(Theme.textTertiary)
                }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.track)
                        Capsule().fill(Theme.accentGradient).frame(width: max(6, g.size.width * vm.overallProgress))
                    }
                }
                .frame(height: 8)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .glassCard()
    }

    private var statRow: some View {
        HStack(spacing: 12) {
            stat(icon: "calendar", label: "Min / Month", value: vm.totalMinimum.currencyWhole)
            stat(icon: "percent", label: "Avg APR", value: String(format: "%.1f%%", vm.avgAPR))
        }
    }

    private func stat(icon: String, label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.caption).foregroundStyle(Theme.accent)
                Text(label.uppercased()).monoLabel(9)
            }
            Text(value).font(Theme.figure(22, weight: .semibold)).foregroundStyle(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassCard(Theme.radiusSmall)
    }

    private var accountsCard: some View {
        ThemedCard(title: "Accounts") {
            VStack(spacing: 16) {
                ForEach(vm.debts) { debt in
                    Button { editing = debt } label: { debtRow(debt) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private func debtRow(_ debt: Debt) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(debt.color.opacity(0.18)).frame(width: 36, height: 36)
                    Image(systemName: debt.type.icon).font(.system(size: 16)).foregroundStyle(debt.color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(debt.name).font(.subheadline.weight(.medium)).foregroundStyle(Theme.textPrimary)
                    Text("\(debt.type.rawValue) · \(debt.interestRate, specifier: "%.1f")% APR")
                        .font(.caption).foregroundStyle(Theme.textTertiary)
                }
                Spacer()
                Text(debt.currentBalance.currencyWhole).font(.subheadline.weight(.bold)).foregroundStyle(Theme.textPrimary)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.track)
                    Capsule().fill(debt.color).frame(width: max(4, g.size.width * debt.progress))
                }
            }
            .frame(height: 6)
        }
        .contentShape(Rectangle())
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Debts Tracked", systemImage: "creditcard.trianglebadge.exclamationmark")
        } description: {
            Text("Add credit cards, loans or mortgages to track balances, rates and payoff progress.")
        } actions: {
            Button("Add Debt") { showAdd = true }
                .buttonStyle(.glassProminent)
        }
    }
}

// MARK: - Add / Edit debt

struct AddDebtView: View {
    @ObservedObject var vm: DebtViewModel
    var editing: Debt? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var type: DebtType = .creditCard
    @State private var originalAmount = ""
    @State private var currentBalance = ""
    @State private var interestRate = ""
    @State private var minimumPayment = ""
    @State private var currencyCode = "USD"
    @State private var dueDay = 1
    @State private var notes = ""
    @State private var showCurrency = false

    private var isValid: Bool { !name.isEmpty && (Double(currentBalance) ?? 0) > 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (e.g. Chase Sapphire)", text: $name)
                    Picker("Type", selection: $type) {
                        ForEach(DebtType.allCases) { t in
                            Label(t.rawValue, systemImage: t.icon).tag(t)
                        }
                    }
                }
                .listRowBackground(Theme.card)

                Section {
                    HStack {
                        Text("Currency"); Spacer()
                        Button(currencyCode) { showCurrency = true }.foregroundStyle(Theme.accent)
                    }
                    numberField("Original Amount", $originalAmount)
                    numberField("Current Balance", $currentBalance)
                    numberField("Interest Rate (APR %)", $interestRate)
                    numberField("Minimum Payment", $minimumPayment)
                }
                .listRowBackground(Theme.card)

                Section {
                    Stepper("Payment Due Day: \(dueDay)", value: $dueDay, in: 1...31)
                    TextField("Notes", text: $notes, axis: .vertical).lineLimit(2...4)
                }
                .listRowBackground(Theme.card)
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .navigationTitle(editing == nil ? "New Debt" : "Edit Debt")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(role: .close) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) { save() }.disabled(!isValid)
                }
            }
            .sheet(isPresented: $showCurrency) { CurrencyPickerView(selectedCode: $currencyCode) }
            .onAppear(perform: prefill)
        }
    }

    private func numberField(_ title: String, _ text: Binding<String>) -> some View {
        HStack {
            Text(title); Spacer()
            TextField("0", text: text)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 130)
        }
    }

    private func prefill() {
        guard let d = editing else { return }
        name = d.name; type = d.type
        originalAmount = d.originalAmount == 0 ? "" : String(d.originalAmount)
        currentBalance = d.currentBalance == 0 ? "" : String(d.currentBalance)
        interestRate = d.interestRate == 0 ? "" : String(d.interestRate)
        minimumPayment = d.minimumPayment == 0 ? "" : String(d.minimumPayment)
        currencyCode = d.currencyCode; dueDay = d.dueDay; notes = d.notes
    }

    private func save() {
        var d = Debt(
            id: editing?.id ?? UUID().uuidString,
            name: name, type: type,
            originalAmount: Double(originalAmount) ?? 0,
            currentBalance: Double(currentBalance) ?? 0,
            interestRate: Double(interestRate) ?? 0,
            minimumPayment: Double(minimumPayment) ?? 0,
            currencyCode: currencyCode, dueDay: dueDay, notes: notes)
        if let editing { d.createdAt = editing.createdAt }
        Task {
            if editing == nil { await vm.add(d) } else { await vm.update(d) }
            dismiss()
        }
    }
}
