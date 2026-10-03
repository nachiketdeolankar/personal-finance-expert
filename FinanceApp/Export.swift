import SwiftUI
import UniformTypeIdentifiers
import CoreGraphics

// MARK: - File documents

struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        text = configuration.file.regularFileContents.map { String(decoding: $0, as: UTF8.self) } ?? ""
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

struct PDFExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Export service

enum ExportService {
    private static func esc(_ s: String) -> String {
        if s.contains(",") || s.contains("\"") || s.contains("\n") {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }
    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    static func expensesCSV(_ expenses: [Expense], categories: [ExpenseCategory]) -> String {
        func catName(_ id: String) -> String { categories.first { $0.id == id }?.name ?? id }
        var rows = ["Date,Title,Category,Amount,Currency,Payment Method,Recurring,Notes"]
        for e in expenses.sorted(by: { $0.date > $1.date }) {
            rows.append([
                dateFmt.string(from: e.date), esc(e.title), esc(catName(e.categoryID)),
                String(format: "%.2f", e.amount), e.currencyCode, esc(e.paymentMethod ?? ""),
                e.isRecurring ? "Yes" : "No", esc(e.notes)
            ].joined(separator: ","))
        }
        return rows.joined(separator: "\n")
    }

    static func investmentsCSV(_ items: [Investment]) -> String {
        var rows = ["Name,Symbol,Type,Quantity,Cost Basis,Current Value,Gain/Loss,Gain %,Currency,Purchase Date,Notes"]
        for i in items {
            rows.append([
                esc(i.name), esc(i.symbol), esc(i.type.rawValue),
                String(format: "%.4f", i.quantity), String(format: "%.2f", i.costBasis),
                String(format: "%.2f", i.currentValue), String(format: "%.2f", i.gainLoss),
                String(format: "%.2f", i.gainLossPercent), i.currencyCode,
                dateFmt.string(from: i.purchaseDate), esc(i.notes)
            ].joined(separator: ","))
        }
        return rows.joined(separator: "\n")
    }

    static func debtsCSV(_ items: [Debt]) -> String {
        var rows = ["Name,Type,Original Amount,Current Balance,APR %,Minimum Payment,Due Day,Currency,Notes"]
        for d in items {
            rows.append([
                esc(d.name), esc(d.type.rawValue),
                String(format: "%.2f", d.originalAmount), String(format: "%.2f", d.currentBalance),
                String(format: "%.2f", d.interestRate), String(format: "%.2f", d.minimumPayment),
                "\(d.dueDay)", d.currencyCode, esc(d.notes)
            ].joined(separator: ","))
        }
        return rows.joined(separator: "\n")
    }

    struct ReportData {
        var monthLabel: String
        var spending: Double
        var txnCount: Int
        var topCategories: [(name: String, amount: Double)]
        var investmentsTotal: Double
        var investmentsGain: Double
        var holdingsCount: Int
        var debtsTotal: Double
        var debtsCount: Int
    }

    @MainActor
    static func reportPDF(_ d: ReportData) -> Data? {
        let renderer = ImageRenderer(content: ReportCanvas(data: d))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("PFE-Report.pdf")
        renderer.render { size, renderInContext in
            var box = CGRect(x: 0, y: 0, width: size.width, height: size.height)
            guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            pdf.beginPDFPage(nil)
            renderInContext(pdf)
            pdf.endPDFPage()
            pdf.closePDF()
        }
        return try? Data(contentsOf: url)
    }
}

// MARK: - PDF report canvas (light, print-friendly)

private struct ReportCanvas: View {
    let data: ExportService.ReportData

    private let lav  = Color(hex: "#6E55E0")!
    private let ink  = Color(hex: "#15161A")!
    private let gray = Color(hex: "#8E8E93")!
    private let red  = Color(hex: "#FF5A5F")!

    private var net: Double { data.investmentsTotal - data.debtsTotal }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Personal Finance Expert").font(.system(size: 22, weight: .bold)).foregroundStyle(ink)
                Text("Financial Report · \(Date().formatted(date: .abbreviated, time: .omitted))")
                    .font(.system(size: 11)).foregroundStyle(gray)
            }
            Rectangle().fill(lav).frame(height: 3).padding(.top, 16).padding(.bottom, 24)

            Text("NET POSITION").font(.system(size: 11, weight: .bold)).tracking(1).foregroundStyle(gray)
            Text(net.currencyWhole)
                .font(.system(size: 40, weight: .heavy, design: .rounded))
                .foregroundStyle(net >= 0 ? lav : red)
            Text("Investments − Debt").font(.system(size: 11)).foregroundStyle(gray).padding(.bottom, 26)

            HStack(spacing: 14) {
                box("SPENDING · \(data.monthLabel)", data.spending.currencyWhole, "\(data.txnCount) transactions")
                box("INVESTMENTS", data.investmentsTotal.currencyWhole,
                    "\(data.holdingsCount) holdings · \(data.investmentsGain >= 0 ? "+" : "")\(data.investmentsGain.currencyWhole)")
                box("DEBT", data.debtsTotal.currencyWhole, "\(data.debtsCount) accounts")
            }
            .padding(.bottom, 28)

            if !data.topCategories.isEmpty {
                Text("TOP CATEGORIES THIS MONTH")
                    .font(.system(size: 11, weight: .bold)).tracking(1).foregroundStyle(gray).padding(.bottom, 8)
                ForEach(Array(data.topCategories.enumerated()), id: \.offset) { _, item in
                    HStack {
                        Text(item.name).font(.system(size: 13)).foregroundStyle(ink)
                        Spacer()
                        Text(item.amount.currencyWhole).font(.system(size: 13, weight: .semibold)).foregroundStyle(ink)
                    }
                    .padding(.vertical, 5)
                    Rectangle().fill(Color(hex: "#E5E5EA")!).frame(height: 0.5)
                }
            }

            Spacer()
            Text("Generated by Personal Finance Expert").font(.system(size: 9)).foregroundStyle(gray)
        }
        .padding(40)
        .frame(width: 612, height: 792, alignment: .topLeading)
        .background(Color.white)
    }

    private func box(_ title: String, _ value: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 9, weight: .bold)).foregroundStyle(gray).lineLimit(1)
            Text(value).font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(ink).lineLimit(1).minimumScaleFactor(0.6)
            Text(sub).font(.system(size: 9)).foregroundStyle(gray).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(hex: "#F4F4F7")!)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Export screen

struct ExportView: View {
    @EnvironmentObject var vm: ExpenseViewModel
    @State private var investments: [Investment] = []
    @State private var debts: [Debt] = []

    @State private var csvDoc: CSVDocument?
    @State private var csvName = "export"
    @State private var showCSV = false

    @State private var pdfDoc: PDFExportDocument?
    @State private var showPDF = false

    var body: some View {
        Form {
            Section {
                row("Expenses", "list.bullet.rectangle.fill", count: vm.expenses.count) {
                    csvName = "expenses"
                    csvDoc = CSVDocument(text: ExportService.expensesCSV(vm.expenses, categories: vm.categories))
                    showCSV = true
                }
                row("Investments", "chart.line.uptrend.xyaxis", count: investments.count) {
                    csvName = "investments"
                    csvDoc = CSVDocument(text: ExportService.investmentsCSV(investments))
                    showCSV = true
                }
                row("Debts", "creditcard.trianglebadge.exclamationmark", count: debts.count) {
                    csvName = "debts"
                    csvDoc = CSVDocument(text: ExportService.debtsCSV(debts))
                    showCSV = true
                }
            } header: {
                Text("CSV — Spreadsheet")
            } footer: {
                Text("Opens a save dialog. CSV files work in Numbers, Excel and Google Sheets.")
            }
            .listRowBackground(Theme.card)

            Section {
                Button { generateReport() } label: {
                    HStack {
                        Label("Financial Report", systemImage: "doc.richtext.fill")
                        Spacer()
                        Image(systemName: "square.and.arrow.up").foregroundStyle(Theme.accent)
                    }
                }
            } header: {
                Text("PDF — Report")
            } footer: {
                Text("A one-page summary: net position, spending, investments and debt.")
            }
            .listRowBackground(Theme.card)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Export")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .fileExporter(isPresented: $showCSV, document: csvDoc,
                      contentType: .commaSeparatedText, defaultFilename: csvName) { _ in }
        .fileExporter(isPresented: $showPDF, document: pdfDoc,
                      contentType: .pdf, defaultFilename: "Financial Report") { _ in }
        .task {
            investments = (try? await CloudKitManager.shared.fetchInvestments()) ?? []
            debts = (try? await CloudKitManager.shared.fetchDebts()) ?? []
        }
    }

    private func row(_ title: String, _ icon: String, count: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: icon)
                Spacer()
                Text("\(count)").foregroundStyle(Theme.textTertiary)
                Image(systemName: "square.and.arrow.up").foregroundStyle(count == 0 ? Theme.textTertiary : Theme.accent)
            }
        }
        .disabled(count == 0)
    }

    private func generateReport() {
        let cal = Calendar.current
        let now = Date()
        let m = cal.component(.month, from: now), y = cal.component(.year, from: now)
        let monthExp = vm.expenses.filter {
            cal.component(.month, from: $0.date) == m && cal.component(.year, from: $0.date) == y
        }
        var byCat: [String: Double] = [:]
        for e in monthExp { byCat[e.categoryID, default: 0] += e.amount }
        let top = byCat.sorted { $0.value > $1.value }.prefix(5).map { pair in
            (name: vm.categories.first { $0.id == pair.key }?.name ?? pair.key, amount: pair.value)
        }
        let data = ExportService.ReportData(
            monthLabel: now.formatted(.dateTime.month(.abbreviated).year()),
            spending: monthExp.reduce(0) { $0 + $1.amount },
            txnCount: monthExp.count,
            topCategories: Array(top),
            investmentsTotal: investments.reduce(0) { $0 + $1.currentValue },
            investmentsGain: investments.reduce(0) { $0 + ($1.currentValue - $1.costBasis) },
            holdingsCount: investments.count,
            debtsTotal: debts.reduce(0) { $0 + $1.currentBalance },
            debtsCount: debts.count
        )
        if let pdf = ExportService.reportPDF(data) {
            pdfDoc = PDFExportDocument(data: pdf)
            showPDF = true
        }
    }
}
