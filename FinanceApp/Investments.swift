import SwiftUI
import Charts
import Combine

// MARK: - Model

enum InvestmentType: String, Codable, CaseIterable, Identifiable {
    case stock      = "Stock"
    case etf        = "ETF"
    case crypto     = "Crypto"
    case mutualFund = "Mutual Fund"
    case bond       = "Bond"
    case realEstate = "Real Estate"
    case other      = "Other"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .stock:      return "chart.line.uptrend.xyaxis"
        case .etf:        return "square.stack.3d.up.fill"
        case .crypto:     return "bitcoinsign.circle.fill"
        case .mutualFund: return "chart.pie.fill"
        case .bond:       return "doc.text.fill"
        case .realEstate: return "house.fill"
        case .other:      return "circle.grid.2x2.fill"
        }
    }

    var colorHex: String {
        switch self {
        case .stock:      return "#6E55E0"
        case .etf:        return "#45B7D1"
        case .crypto:     return "#F8B500"
        case .mutualFund: return "#55EFC4"
        case .bond:       return "#FF6B9D"
        case .realEstate: return "#96CEB4"
        case .other:      return "#B2BEC3"
        }
    }

    var color: Color { Color(hex: colorHex) ?? Theme.accent }
}

struct Investment: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var symbol: String
    var type: InvestmentType
    var quantity: Double
    var costBasis: Double      // total invested
    var currentValue: Double   // current market value
    var currencyCode: String
    var purchaseDate: Date
    var notes: String
    var createdAt: Date
    var updatedAt: Date

    init(id: String = UUID().uuidString, name: String, symbol: String = "",
         type: InvestmentType = .stock, quantity: Double = 0, costBasis: Double = 0,
         currentValue: Double = 0, currencyCode: String = "USD",
         purchaseDate: Date = Date(), notes: String = "") {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.type = type
        self.quantity = quantity
        self.costBasis = costBasis
        self.currentValue = currentValue
        self.currencyCode = currencyCode
        self.purchaseDate = purchaseDate
        self.notes = notes
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var currency: Currency { Currency.all.first { $0.code == currencyCode } ?? .usd }
    var gainLoss: Double { currentValue - costBasis }
    var gainLossPercent: Double { costBasis > 0 ? gainLoss / costBasis * 100 : 0 }
    var color: Color { type.color }
}

// MARK: - View Model

@MainActor
final class InvestmentViewModel: ObservableObject {
    @Published var investments: [Investment] = []
    @Published var isLoading = false
    @Published var error: String?

    private let ck = CloudKitManager.shared

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do { investments = try await ck.fetchInvestments() }
        catch { self.error = error.localizedDescription }
    }

    func add(_ inv: Investment) async {
        do { try await ck.saveInvestment(inv); investments.insert(inv, at: 0) }
        catch { self.error = error.localizedDescription }
    }

    func update(_ inv: Investment) async {
        do {
            try await ck.saveInvestment(inv)
            if let i = investments.firstIndex(where: { $0.id == inv.id }) { investments[i] = inv }
        } catch { self.error = error.localizedDescription }
    }

    func delete(_ inv: Investment) async {
        do { try await ck.deleteInvestment(inv); investments.removeAll { $0.id == inv.id } }
        catch { self.error = error.localizedDescription }
    }

    var totalValue: Double { investments.reduce(0) { $0 + $1.currentValue } }
    var totalCost: Double  { investments.reduce(0) { $0 + $1.costBasis } }
    var totalGainLoss: Double { totalValue - totalCost }
    var totalGainLossPercent: Double { totalCost > 0 ? totalGainLoss / totalCost * 100 : 0 }

    var allocation: [(type: InvestmentType, value: Double)] {
        var byType: [InvestmentType: Double] = [:]
        for inv in investments { byType[inv.type, default: 0] += inv.currentValue }
        return byType.map { (type: $0.key, value: $0.value) }.sorted { $0.value > $1.value }
    }
}

// MARK: - Investments screen

struct InvestmentsView: View {
    @StateObject private var vm = InvestmentViewModel()
    @State private var showAdd = false
    @State private var editing: Investment?

    var body: some View {
        Group {
            if vm.investments.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: Theme.spacing) {
                        portfolioCard
                        if vm.allocation.count > 1 { allocationCard }
                        holdingsCard
                    }
                    .padding(Theme.spacing)
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .navigationTitle("Investments")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Investment", systemImage: "plus") { editing = nil; showAdd = true }
            }
        }
        .sheet(isPresented: $showAdd) { AddInvestmentView(vm: vm) }
        .sheet(item: $editing) { inv in AddInvestmentView(vm: vm, editing: inv) }
        .task { await vm.load() }
    }

    private var portfolioCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PORTFOLIO VALUE")
                .monoLabel()
            Text(vm.totalValue.currencyWhole)
                .font(Theme.figure(42))
                .foregroundStyle(Theme.textPrimary)
            HStack(spacing: 6) {
                Image(systemName: vm.totalGainLoss >= 0 ? "arrow.up.right" : "arrow.down.right")
                Text("\(vm.totalGainLoss >= 0 ? "+" : "")\(vm.totalGainLoss.currencyWhole) (\(vm.totalGainLossPercent, specifier: "%.1f")%)")
            }
            .font(.subheadline.weight(.bold))
            .foregroundStyle(vm.totalGainLoss >= 0 ? Theme.accent : Theme.danger)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background((vm.totalGainLoss >= 0 ? Theme.accent : Theme.danger).opacity(0.14), in: Capsule())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .glassCard()
    }

    private var allocationCard: some View {
        ThemedCard(title: "Allocation") {
            HStack(alignment: .center, spacing: 20) {
                Chart(vm.allocation, id: \.type.id) { item in
                    SectorMark(angle: .value("Value", item.value), innerRadius: .ratio(0.62), angularInset: 2)
                        .foregroundStyle(item.type.color)
                        .cornerRadius(3)
                }
                .chartLegend(.hidden)
                .frame(width: 120, height: 120)

                VStack(alignment: .leading, spacing: 9) {
                    ForEach(vm.allocation, id: \.type.id) { item in
                        HStack(spacing: 8) {
                            Circle().fill(item.type.color).frame(width: 9, height: 9)
                            Text(item.type.rawValue).font(.caption).foregroundStyle(Theme.textSecondary)
                            Spacer()
                            Text(item.value.currencyWhole).font(.caption.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                        }
                    }
                }
            }
        }
    }

    private var holdingsCard: some View {
        ThemedCard(title: "Holdings") {
            VStack(spacing: 0) {
                ForEach(Array(vm.investments.enumerated()), id: \.element.id) { idx, inv in
                    Button { editing = inv } label: { holdingRow(inv) }
                        .buttonStyle(.plain)
                    if idx < vm.investments.count - 1 {
                        Rectangle().fill(Theme.divider).frame(height: 0.5).padding(.leading, 46)
                    }
                }
            }
        }
    }

    private func holdingRow(_ inv: Investment) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(inv.color.opacity(0.18)).frame(width: 36, height: 36)
                Image(systemName: inv.type.icon).font(.system(size: 16)).foregroundStyle(inv.color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(inv.name).font(.subheadline.weight(.medium)).foregroundStyle(Theme.textPrimary)
                Text(inv.symbol.isEmpty ? inv.type.rawValue : inv.symbol)
                    .font(.caption).foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(inv.currentValue.currencyWhole).font(.subheadline.weight(.bold)).foregroundStyle(Theme.textPrimary)
                Text("\(inv.gainLoss >= 0 ? "+" : "")\(inv.gainLossPercent, specifier: "%.1f")%")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(inv.gainLoss >= 0 ? Theme.accent : Theme.danger)
            }
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Investments Yet", systemImage: "chart.line.uptrend.xyaxis")
        } description: {
            Text("Track stocks, ETFs, crypto and more to see your portfolio value and gains.")
        } actions: {
            Button("Add Investment") { showAdd = true }
                .buttonStyle(.glassProminent)
        }
    }
}

// MARK: - Add / Edit investment

struct AddInvestmentView: View {
    @ObservedObject var vm: InvestmentViewModel
    var editing: Investment? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var symbol = ""
    @State private var type: InvestmentType = .stock
    @State private var quantity = ""
    @State private var costBasis = ""
    @State private var currentValue = ""
    @State private var currencyCode = "USD"
    @State private var purchaseDate = Date()
    @State private var notes = ""
    @State private var showCurrency = false

    private var isValid: Bool { !name.isEmpty && (Double(currentValue) ?? 0) > 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (e.g. Apple Inc.)", text: $name)
                    TextField("Symbol (e.g. AAPL)", text: $symbol)
                        #if os(iOS)
                        .textInputAutocapitalization(.characters)
                        #endif
                    Picker("Type", selection: $type) {
                        ForEach(InvestmentType.allCases) { t in
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
                    numberField("Quantity", $quantity)
                    numberField("Amount Invested", $costBasis)
                    numberField("Current Value", $currentValue)
                }
                .listRowBackground(Theme.card)

                Section {
                    DatePicker("Purchase Date", selection: $purchaseDate, displayedComponents: .date)
                    TextField("Notes", text: $notes, axis: .vertical).lineLimit(2...4)
                }
                .listRowBackground(Theme.card)
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .navigationTitle(editing == nil ? "New Investment" : "Edit Investment")
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
                .frame(maxWidth: 140)
        }
    }

    private func prefill() {
        guard let inv = editing else { return }
        name = inv.name; symbol = inv.symbol; type = inv.type
        quantity = inv.quantity == 0 ? "" : String(inv.quantity)
        costBasis = inv.costBasis == 0 ? "" : String(inv.costBasis)
        currentValue = inv.currentValue == 0 ? "" : String(inv.currentValue)
        currencyCode = inv.currencyCode; purchaseDate = inv.purchaseDate; notes = inv.notes
    }

    private func save() {
        var inv = Investment(
            id: editing?.id ?? UUID().uuidString,
            name: name, symbol: symbol, type: type,
            quantity: Double(quantity) ?? 0,
            costBasis: Double(costBasis) ?? 0,
            currentValue: Double(currentValue) ?? 0,
            currencyCode: currencyCode, purchaseDate: purchaseDate, notes: notes)
        if let editing { inv.createdAt = editing.createdAt }
        Task {
            if editing == nil { await vm.add(inv) } else { await vm.update(inv) }
            dismiss()
        }
    }
}
