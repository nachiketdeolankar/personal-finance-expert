import WidgetKit
import SwiftUI

// Personal Finance Expert — widget extension (all widgets in one file).
//
// MAC SETUP (one-time, in Xcode):
//   1. File → New → Target → Widget Extension. Name: PersonalFinanceWidgets.
//      Platform iOS. UNCHECK "Include Configuration App Intent".
//   2. Delete the template .swift files Xcode generated for the target and add
//      this file (repo root: PersonalFinanceWidgets/PersonalFinanceWidgets.swift)
//      to the widget target instead.
//   3. Signing & Capabilities → add "App Groups" to BOTH the app target and this
//      widget target, with the group:  group.com.nachi.personalfinance
//      (App Groups works on the free personal team — iCloud/Push still do not.)
//   4. Build & run the app once — it writes widget_snapshot.json into the App
//      Group on every data change; widgets read only that file.
//
// Design: Direction C — graphite, serif figures, mono labels, color = meaning.
// Data model must stay in sync with WidgetSnapshot in FinanceApp/CloudKit/CloudKitManager.swift.

// MARK: - Snapshot model (read-side copy)

struct WidgetSnapshot: Codable {
    var date: Date
    var currencyCode: String
    var maskAmounts: Bool
    var netWorth: Double
    var netWorthDeltaPercent: Double?
    var history: [Double]
    var monthSpent: Double
    var monthBudget: Double
    var budgets: [BudgetStat]
    var budgetsOnTrack: Int
    var budgetsTotal: Int
    var bills: [Bill]
    var billsThisWeekCount: Int
    var billsThisWeekTotal: Double
    var biggestExpenseTitle: String?
    var biggestExpenseAmount: Double?

    struct BudgetStat: Codable { var name: String; var spent: Double; var limit: Double }
    struct Bill: Codable { var title: String; var amount: Double; var date: Date }

    static let placeholder = WidgetSnapshot(
        date: .now, currencyCode: "USD", maskAmounts: false,
        netWorth: 128_540, netWorthDeltaPercent: 2.4,
        history: [118, 119.5, 119, 121, 120.5, 123, 122.5, 125, 126, 128.5].map { $0 * 1000 },
        monthSpent: 2184, monthBudget: 3000,
        budgets: [.init(name: "Food & Dining", spent: 492, limit: 600),
                  .init(name: "Groceries", spent: 318, limit: 520),
                  .init(name: "Transport", spent: 247, limit: 220)],
        budgetsOnTrack: 2, budgetsTotal: 3,
        bills: [.init(title: "Netflix", amount: 15.49, date: .now.addingTimeInterval(3 * 86400)),
                .init(title: "Rent", amount: 1850, date: .now.addingTimeInterval(7 * 86400)),
                .init(title: "iCloud+", amount: 2.99, date: .now.addingTimeInterval(9 * 86400))],
        billsThisWeekCount: 3, billsThisWeekTotal: 1868,
        biggestExpenseTitle: "Whole Foods", biggestExpenseAmount: 86.12
    )
}

private let appGroupID = "group.com.nachi.personalfinance"

private func loadSnapshot() -> WidgetSnapshot? {
    guard let container = FileManager.default
        .containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else { return nil }
    let url = container.appendingPathComponent("widget_snapshot.json")
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
}

// MARK: - Timeline

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snap: WidgetSnapshot?
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snap: .placeholder)
    }
    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: .now, snap: loadSnapshot() ?? .placeholder))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        // The app reloads timelines on every data change — no self-refresh needed.
        completion(Timeline(entries: [SnapshotEntry(date: .now, snap: loadSnapshot())], policy: .never))
    }
}

// MARK: - Style

private enum W {
    static let ink   = Color(red: 0.93, green: 0.94, blue: 0.95)
    static let mut   = Color(red: 0.56, green: 0.58, blue: 0.63)
    static let line  = Color.white.opacity(0.09)
    static let accent = Color(red: 0.78, green: 0.80, blue: 0.85)   // silver #C7CDD8
    static let good  = Color(red: 0.39, green: 0.79, blue: 0.60)
    static let bad   = Color(red: 0.90, green: 0.39, blue: 0.42)
    static let gradient = LinearGradient(
        colors: [Color(red: 0.14, green: 0.15, blue: 0.18),
                 Color(red: 0.08, green: 0.09, blue: 0.11)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
}

private extension View {
    func wLabel() -> some View {
        self.font(.system(size: 9, weight: .medium, design: .monospaced))
            .tracking(1.2)
            .foregroundStyle(W.mut)
            .textCase(.uppercase)
    }
    func widgetChrome() -> some View {
        self.containerBackground(for: .widget) { W.gradient }
    }
}

private func money(_ value: Double, _ snap: WidgetSnapshot?, fraction: Int = 0) -> String {
    if snap?.maskAmounts == true { return "••••" }
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.currencyCode = snap?.currencyCode ?? "USD"
    f.maximumFractionDigits = fraction
    return f.string(from: NSNumber(value: value)) ?? "—"
}

private struct Sparkline: View {
    let values: [Double]
    var body: some View {
        GeometryReader { geo in
            let pts = normalized(in: geo.size)
            ZStack {
                Path { p in
                    guard let first = pts.first else { return }
                    p.move(to: CGPoint(x: first.x, y: geo.size.height))
                    p.addLine(to: first)
                    for pt in pts.dropFirst() { p.addLine(to: pt) }
                    p.addLine(to: CGPoint(x: pts.last!.x, y: geo.size.height))
                    p.closeSubpath()
                }
                .fill(W.accent.opacity(0.12))
                Path { p in
                    guard let first = pts.first else { return }
                    p.move(to: first)
                    for pt in pts.dropFirst() { p.addLine(to: pt) }
                }
                .stroke(W.accent, lineWidth: 1.5)
                if let last = pts.last {
                    Circle().fill(W.accent).frame(width: 4, height: 4)
                        .position(last)
                }
            }
        }
    }
    private func normalized(in size: CGSize) -> [CGPoint] {
        guard values.count > 1,
              let lo = values.min(), let hi = values.max(), hi > lo else {
            return [CGPoint(x: 0, y: size.height / 2),
                    CGPoint(x: size.width, y: size.height / 2)]
        }
        let stepX = size.width / CGFloat(values.count - 1)
        return values.enumerated().map { i, v in
            CGPoint(x: CGFloat(i) * stepX,
                    y: size.height - (size.height - 4) * CGFloat((v - lo) / (hi - lo)) - 2)
        }
    }
}

private struct BudgetBar: View {
    let stat: WidgetSnapshot.BudgetStat
    let snap: WidgetSnapshot?
    var body: some View {
        let over = stat.spent > stat.limit
        let progress = stat.limit > 0 ? min(stat.spent / stat.limit, 1) : 0
        VStack(spacing: 3) {
            HStack {
                Text(stat.name).font(.system(size: 11)).foregroundStyle(W.ink).lineLimit(1)
                Spacer()
                Text("\(money(stat.spent, snap)) / \(money(stat.limit, snap))")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(over ? W.bad : W.mut)
                    .privacySensitive()
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(W.line)
                    Capsule().fill(over ? W.bad : W.accent)
                        .frame(width: max(3, g.size.width * progress))
                }
            }
            .frame(height: 4)
        }
    }
}

private struct EmptyHint: View {
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "arrow.up.forward.app").foregroundStyle(W.mut)
            Text("Open the app once\nto load your data")
                .font(.system(size: 9)).multilineTextAlignment(.center)
                .foregroundStyle(W.mut)
        }
    }
}

// MARK: - S1 · Net Worth (small)

struct NetWorthWidgetView: View {
    let entry: SnapshotEntry
    var body: some View {
        Group {
            if let s = entry.snap {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Net Worth").wLabel()
                    Text(money(s.netWorth, s))
                        .font(.system(size: 24, design: .serif))
                        .foregroundStyle(W.ink)
                        .minimumScaleFactor(0.6).lineLimit(1)
                        .privacySensitive()
                    if let d = s.netWorthDeltaPercent {
                        Text("\(d >= 0 ? "▲" : "▼") \(abs(d), specifier: "%.1f")% this month")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(d >= 0 ? W.good : W.bad)
                    }
                    Spacer(minLength: 2)
                    Sparkline(values: s.history).frame(height: 30)
                }
            } else { EmptyHint() }
        }
        .widgetChrome()
        .widgetURL(URL(string: "pfe://overview"))
    }
}

struct NetWorthWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "networth", provider: SnapshotProvider()) {
            NetWorthWidgetView(entry: $0)
        }
        .configurationDisplayName("Net Worth")
        .description("Your net worth with its recent trend.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - S2 · Budget ring (small)

struct BudgetRingWidgetView: View {
    let entry: SnapshotEntry
    var body: some View {
        Group {
            if let s = entry.snap {
                let progress = s.monthBudget > 0 ? min(s.monthSpent / s.monthBudget, 1) : 0
                VStack(alignment: .leading, spacing: 4) {
                    Text(s.date.formatted(.dateTime.month(.wide)) + " Spend").wLabel()
                    Spacer(minLength: 0)
                    HStack(spacing: 10) {
                        ZStack {
                            Circle().stroke(W.line, lineWidth: 6)
                            Circle().trim(from: 0, to: progress)
                                .stroke(s.monthSpent > s.monthBudget && s.monthBudget > 0 ? W.bad : W.accent,
                                        style: StrokeStyle(lineWidth: 6, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                            Text(s.monthBudget > 0 ? "\(Int(progress * 100))%" : "—")
                                .font(.system(size: 13, design: .serif)).foregroundStyle(W.ink)
                        }
                        .frame(width: 52, height: 52)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(money(s.monthSpent, s))
                                .font(.system(size: 17, design: .serif)).foregroundStyle(W.ink)
                                .minimumScaleFactor(0.6).lineLimit(1)
                                .privacySensitive()
                            Text(s.monthBudget > 0 ? "of \(money(s.monthBudget, s))" : "no budget set")
                                .font(.system(size: 8)).foregroundStyle(W.mut)
                        }
                    }
                    Spacer(minLength: 0)
                }
            } else { EmptyHint() }
        }
        .widgetChrome()
        .widgetURL(URL(string: "pfe://overview"))
    }
}

struct BudgetRingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "budgetring", provider: SnapshotProvider()) {
            BudgetRingWidgetView(entry: $0)
        }
        .configurationDisplayName("Month Spend")
        .description("This month's spending against your budget.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - S3 · Quick log (small)

struct QuickLogWidgetView: View {
    let entry: SnapshotEntry
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().fill(Color.white.opacity(0.10))
                Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                Image(systemName: "plus").font(.system(size: 22, weight: .light))
                    .foregroundStyle(W.ink)
            }
            .frame(width: 50, height: 50)
            Text("Log Expense").wLabel()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetChrome()
        .widgetURL(URL(string: "pfe://add"))
    }
}

struct QuickLogWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "quicklog", provider: SnapshotProvider()) {
            QuickLogWidgetView(entry: $0)
        }
        .configurationDisplayName("Quick Log")
        .description("Jump straight into logging an expense.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - M1 · Overview split (medium)

struct OverviewWidgetView: View {
    let entry: SnapshotEntry
    var body: some View {
        Group {
            if let s = entry.snap {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Net Worth").wLabel()
                        Text(money(s.netWorth, s))
                            .font(.system(size: 22, design: .serif)).foregroundStyle(W.ink)
                            .minimumScaleFactor(0.6).lineLimit(1)
                            .privacySensitive()
                        if let d = s.netWorthDeltaPercent {
                            Text("\(d >= 0 ? "▲" : "▼") \(abs(d), specifier: "%.1f")%")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(d >= 0 ? W.good : W.bad)
                        }
                        Spacer(minLength: 2)
                        Sparkline(values: s.history).frame(height: 24)
                    }
                    Rectangle().fill(W.line).frame(width: 1)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(s.date.formatted(.dateTime.month(.wide))) Spend").wLabel()
                        Text(money(s.monthSpent, s))
                            .font(.system(size: 22, design: .serif)).foregroundStyle(W.ink)
                            .minimumScaleFactor(0.6).lineLimit(1)
                            .privacySensitive()
                        if s.monthBudget > 0 {
                            Text("\(Int(min(s.monthSpent / s.monthBudget, 9.99) * 100))% of budget")
                                .font(.system(size: 9)).foregroundStyle(W.mut)
                        }
                        Spacer(minLength: 2)
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(W.line)
                                if s.monthBudget > 0 {
                                    Capsule()
                                        .fill(s.monthSpent > s.monthBudget ? W.bad : W.accent)
                                        .frame(width: max(3, g.size.width * min(s.monthSpent / s.monthBudget, 1)))
                                }
                            }
                        }
                        .frame(height: 4)
                    }
                }
            } else { EmptyHint().frame(maxWidth: .infinity) }
        }
        .widgetChrome()
        .widgetURL(URL(string: "pfe://overview"))
    }
}

struct OverviewWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "overview", provider: SnapshotProvider()) {
            OverviewWidgetView(entry: $0)
        }
        .configurationDisplayName("Overview")
        .description("Net worth and month spend, side by side.")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - M2 · Budgets (medium)

struct BudgetsWidgetView: View {
    let entry: SnapshotEntry
    var body: some View {
        Group {
            if let s = entry.snap, !s.budgets.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Budgets · \(s.date.formatted(.dateTime.month(.wide)))").wLabel()
                    ForEach(Array(s.budgets.prefix(3).enumerated()), id: \.offset) { _, stat in
                        BudgetBar(stat: stat, snap: s)
                    }
                    Spacer(minLength: 0)
                }
            } else if entry.snap != nil {
                VStack(spacing: 4) {
                    Text("Budgets").wLabel()
                    Text("No budgets set this month")
                        .font(.system(size: 11)).foregroundStyle(W.mut)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else { EmptyHint().frame(maxWidth: .infinity) }
        }
        .widgetChrome()
        .widgetURL(URL(string: "pfe://overview"))
    }
}

struct BudgetsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "budgets", provider: SnapshotProvider()) {
            BudgetsWidgetView(entry: $0)
        }
        .configurationDisplayName("Budgets")
        .description("Your top budgets — red only when over.")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - M3 · Upcoming bills (medium)

struct BillsWidgetView: View {
    let entry: SnapshotEntry
    var body: some View {
        Group {
            if let s = entry.snap, !s.bills.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Upcoming Bills").wLabel().padding(.bottom, 6)
                    ForEach(Array(s.bills.prefix(3).enumerated()), id: \.offset) { i, bill in
                        HStack(spacing: 8) {
                            Text(bill.date.formatted(.dateTime.month(.abbreviated).day()))
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundStyle(W.mut)
                                .frame(width: 44, alignment: .leading)
                            Text(bill.title).font(.system(size: 12)).foregroundStyle(W.ink).lineLimit(1)
                            Spacer()
                            Text(money(bill.amount, s, fraction: 2))
                                .font(.system(size: 12, weight: .semibold)).foregroundStyle(W.ink)
                                .privacySensitive()
                        }
                        .frame(maxHeight: .infinity)
                        if i < min(s.bills.count, 3) - 1 {
                            Rectangle().fill(W.line).frame(height: 1)
                        }
                    }
                }
            } else if entry.snap != nil {
                VStack(spacing: 4) {
                    Text("Upcoming Bills").wLabel()
                    Text("Nothing due — add recurring expenses in the app")
                        .font(.system(size: 11)).foregroundStyle(W.mut)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else { EmptyHint().frame(maxWidth: .infinity) }
        }
        .widgetChrome()
        .widgetURL(URL(string: "pfe://recurring"))
    }
}

struct BillsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "bills", provider: SnapshotProvider()) {
            BillsWidgetView(entry: $0)
        }
        .configurationDisplayName("Upcoming Bills")
        .description("Your next recurring payments.")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - L1 · Money board (large)

struct BoardWidgetView: View {
    let entry: SnapshotEntry
    var body: some View {
        Group {
            if let s = entry.snap {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Net Worth").wLabel()
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(money(s.netWorth, s))
                            .font(.system(size: 28, design: .serif)).foregroundStyle(W.ink)
                            .privacySensitive()
                        if let d = s.netWorthDeltaPercent {
                            Text("\(d >= 0 ? "▲" : "▼") \(abs(d), specifier: "%.1f")%")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(d >= 0 ? W.good : W.bad)
                        }
                    }
                    Sparkline(values: s.history).frame(height: 46)
                    Rectangle().fill(W.line).frame(height: 1).padding(.vertical, 6)
                    LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading),
                                        GridItem(.flexible(), alignment: .leading)],
                              spacing: 14) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(s.date.formatted(.dateTime.month(.wide))) Spend").wLabel()
                            Text(money(s.monthSpent, s))
                                .font(.system(size: 17, design: .serif)).foregroundStyle(W.ink)
                                .privacySensitive()
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Budgets").wLabel()
                            Text(s.budgetsTotal > 0
                                 ? "\(s.budgetsOnTrack) of \(s.budgetsTotal) on track"
                                 : "None set")
                                .font(.system(size: 13, weight: .semibold)).foregroundStyle(W.ink)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Next Bill").wLabel()
                            Text(s.bills.first.map {
                                "\($0.title) · \($0.date.formatted(.dateTime.month(.abbreviated).day()))"
                            } ?? "None")
                                .font(.system(size: 13, weight: .semibold)).foregroundStyle(W.ink)
                                .lineLimit(1)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Biggest Expense").wLabel()
                            Text(s.biggestExpenseTitle.map {
                                "\($0) · \(money(s.biggestExpenseAmount ?? 0, s))"
                            } ?? "—")
                                .font(.system(size: 13, weight: .semibold)).foregroundStyle(W.ink)
                                .lineLimit(1)
                                .privacySensitive()
                        }
                    }
                    Spacer(minLength: 0)
                }
            } else { EmptyHint().frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .widgetChrome()
        .widgetURL(URL(string: "pfe://overview"))
    }
}

struct BoardWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "board", provider: SnapshotProvider()) {
            BoardWidgetView(entry: $0)
        }
        .configurationDisplayName("Money Board")
        .description("The whole overview at a glance.")
        .supportedFamilies([.systemLarge])
    }
}

// MARK: - Lock screen · circular budget gauge

struct GaugeWidgetView: View {
    let entry: SnapshotEntry
    var body: some View {
        Group {
            if let s = entry.snap, s.monthBudget > 0 {
                Gauge(value: min(s.monthSpent / s.monthBudget, 1)) {
                    Text("BUD")
                } currentValueLabel: {
                    Text("\(Int(min(s.monthSpent / s.monthBudget, 9.99) * 100))%")
                        .font(.system(size: 14, design: .serif))
                }
                .gaugeStyle(.accessoryCircular)
            } else {
                Gauge(value: 0) { Text("BUD") } currentValueLabel: {
                    Text("—")
                }
                .gaugeStyle(.accessoryCircular)
            }
        }
        .containerBackground(for: .widget) { Color.clear }
        .widgetURL(URL(string: "pfe://overview"))
    }
}

struct GaugeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "gauge", provider: SnapshotProvider()) {
            GaugeWidgetView(entry: $0)
        }
        .configurationDisplayName("Budget Gauge")
        .description("How much of this month's budget is used.")
        .supportedFamilies([.accessoryCircular])
    }
}

// MARK: - Lock screen · month spend (rectangular)

struct LockSpendWidgetView: View {
    let entry: SnapshotEntry
    var body: some View {
        Group {
            if let s = entry.snap {
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(s.date.formatted(.dateTime.month(.wide))) · Spent")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .textCase(.uppercase)
                        .opacity(0.7)
                    HStack(spacing: 5) {
                        Text(money(s.monthSpent, s))
                            .font(.system(size: 16, design: .serif))
                            .privacySensitive()
                        if s.monthBudget > 0 {
                            Text("· \(Int(min(s.monthSpent / s.monthBudget, 9.99) * 100))% of budget")
                                .font(.system(size: 10)).opacity(0.7)
                        }
                    }
                }
            } else {
                Text("Open Personal Finance Expert").font(.system(size: 11))
            }
        }
        .containerBackground(for: .widget) { Color.clear }
        .widgetURL(URL(string: "pfe://overview"))
    }
}

struct LockSpendWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "lockspend", provider: SnapshotProvider()) {
            LockSpendWidgetView(entry: $0)
        }
        .configurationDisplayName("Month Spend")
        .description("This month's total on your Lock Screen.")
        .supportedFamilies([.accessoryRectangular])
    }
}

// MARK: - Lock screen · bills due (rectangular)

struct LockBillsWidgetView: View {
    let entry: SnapshotEntry
    var body: some View {
        Group {
            if let s = entry.snap {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Bills This Week")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .textCase(.uppercase)
                        .opacity(0.7)
                    Text(s.billsThisWeekCount == 0
                         ? "Nothing due"
                         : "\(s.billsThisWeekCount) due · \(money(s.billsThisWeekTotal, s)) total")
                        .font(.system(size: 13, weight: .semibold))
                        .privacySensitive()
                }
            } else {
                Text("Open Personal Finance Expert").font(.system(size: 11))
            }
        }
        .containerBackground(for: .widget) { Color.clear }
        .widgetURL(URL(string: "pfe://recurring"))
    }
}

struct LockBillsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "lockbills", provider: SnapshotProvider()) {
            LockBillsWidgetView(entry: $0)
        }
        .configurationDisplayName("Bills Due")
        .description("Recurring payments due this week.")
        .supportedFamilies([.accessoryRectangular])
    }
}

// MARK: - Bundle

@main
struct PersonalFinanceWidgets: WidgetBundle {
    var body: some Widget {
        NetWorthWidget()
        BudgetRingWidget()
        QuickLogWidget()
        OverviewWidget()
        BudgetsWidget()
        BillsWidget()
        BoardWidget()
        GaugeWidget()
        LockSpendWidget()
        LockBillsWidget()
    }
}
