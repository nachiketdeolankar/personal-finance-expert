import SwiftUI
import PhotosUI
import Vision
import ImageIO
#if os(iOS)
import UIKit
#endif

struct AddExpenseView: View {
    @EnvironmentObject var vm: ExpenseViewModel
    @Environment(\.dismiss) private var dismiss

    var editingExpense: Expense? = nil

    @State private var title: String = ""
    @State private var amountText: String = ""
    @State private var selectedCurrencyCode: String = "USD"
    @State private var selectedCategoryID: String = "food"
    @State private var date: Date = Date()
    @State private var notes: String = ""
    @State private var isRecurring: Bool = false
    @State private var recurringFrequency: RecurringFrequency = .monthly
    @State private var paymentMethod: String = "Cash"

    @State private var receiptItem: PhotosPickerItem?
    @State private var receiptImage: Image?
    @State private var receiptData: Data?
    @State private var detectedAmount: Double?
    @State private var userPickedCategory: Bool = false

    @State private var showCurrencyPicker: Bool = false
    @State private var showCamera: Bool = false
    @State private var isSaving: Bool = false

    private let paymentMethods = ["Cash", "Credit Card", "Debit Card", "Bank"]

    var isEditing: Bool { editingExpense != nil }
    private var isValid: Bool { !title.isEmpty && (Double(amountText) ?? 0) > 0 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    amountCard
                    detailsCard
                    categorySection
                    paidWithSection
                    receiptSection
                }
                .padding(16)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.background)
            .navigationTitle(isEditing ? "Edit Expense" : "New Expense")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) { save() }
                        .disabled(!isValid || isSaving)
                }
            }
            .sheet(isPresented: $showCurrencyPicker) {
                CurrencyPickerView(selectedCode: $selectedCurrencyCode)
            }
            #if os(iOS)
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker(isPresented: $showCamera) { setReceipt($0) }
                    .ignoresSafeArea()
            }
            #endif
            .onChange(of: receiptItem) { _, item in Task { await loadReceipt(from: item) } }
            .onChange(of: title) { _, newTitle in applyMerchantMemory(newTitle) }
            .onAppear { prefill() }
        }
    }

    // MARK: - Amount card

    private var amountCard: some View {
        VStack(spacing: 14) {
            Button { showCurrencyPicker = true } label: {
                Text(selectedCurrencyCode)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Theme.accentSoft, in: Capsule())
            }
            .buttonStyle(.plain)

            TextField("0.00", text: $amountText)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
                .multilineTextAlignment(.center)
                .font(.system(size: 48, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .textFieldStyle(.plain)

            TextField("What was it for?", text: $title)
                .multilineTextAlignment(.center)
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
                .textFieldStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26).padding(.horizontal, 18)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
            .strokeBorder(Theme.divider, lineWidth: 0.5))
    }

    // MARK: - Details (date, note, recurring)

    private var detailsCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Date").foregroundStyle(Theme.textSecondary)
                Spacer()
                DatePicker("", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
            }
            .padding(.vertical, 12)
            Divider().overlay(Theme.divider)
            HStack {
                Text("Note").foregroundStyle(Theme.textSecondary)
                Spacer()
                TextField("Optional…", text: $notes)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(Theme.textPrimary)
                    .textFieldStyle(.plain)
            }
            .padding(.vertical, 12)
            Divider().overlay(Theme.divider)
            Toggle(isOn: $isRecurring) {
                Text("Recurring").foregroundStyle(Theme.textSecondary)
            }
            .tint(Theme.accent)
            .padding(.vertical, 6)
            if isRecurring {
                Divider().overlay(Theme.divider)
                HStack {
                    Text("Repeat").foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Picker("", selection: $recurringFrequency) {
                        ForEach(RecurringFrequency.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden().tint(Theme.accent)
                }
                .padding(.vertical, 6)
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
            .strokeBorder(Theme.divider, lineWidth: 0.5))
    }

    // MARK: - Category

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("CATEGORY")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(vm.categories) { cat in
                        let selected = selectedCategoryID == cat.id
                        Button { selectedCategoryID = cat.id; userPickedCategory = true } label: {
                            VStack(spacing: 6) {
                                ZStack {
                                    Circle()
                                        .fill(selected ? cat.color : Theme.fill)
                                        .frame(width: 52, height: 52)
                                    Image(systemName: cat.iconName)
                                        .font(.system(size: 20))
                                        .foregroundStyle(selected ? .white : cat.color)
                                }
                                Text(cat.name)
                                    .font(.caption2)
                                    .foregroundStyle(selected ? Theme.textPrimary : Theme.textTertiary)
                                    .lineLimit(1)
                            }
                            .frame(width: 66)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    // MARK: - Paid with

    private var paidWithSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("PAID WITH")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(paymentMethods, id: \.self) { method in
                        let selected = paymentMethod == method
                        Button { paymentMethod = method } label: {
                            Text(method)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(selected ? Theme.accent : Theme.textSecondary)
                                .padding(.horizontal, 16).padding(.vertical, 9)
                                .background(selected ? Theme.accentSoft : Theme.card, in: Capsule())
                                .overlay(Capsule().strokeBorder(selected ? Theme.accent.opacity(0.5) : Theme.divider, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }

    // MARK: - Receipt

    private var receiptSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("RECEIPT")
            if let img = receiptImage {
                VStack(spacing: 8) {
                    ZStack(alignment: .topTrailing) {
                        img.resizable().scaledToFit().frame(maxHeight: 220)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall))
                        Button {
                            receiptImage = nil; receiptData = nil; receiptItem = nil
                            detectedAmount = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3).foregroundStyle(.white, .black.opacity(0.5))
                                .padding(8)
                        }
                        .buttonStyle(.plain)
                    }
                    if let detected = detectedAmount,
                       String(format: "%.2f", detected) != amountText {
                        HStack(spacing: 8) {
                            Image(systemName: "text.viewfinder")
                                .font(.caption).foregroundStyle(Theme.accent)
                            Text("Detected total: \(formattedDetected(detected))")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Theme.textSecondary)
                            Spacer()
                            Button("Use") {
                                amountText = String(format: "%.2f", detected)
                            }
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.accent)
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: Theme.radiusSmall))
                    }
                }
            } else {
                HStack(spacing: 10) {
                    #if os(iOS)
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button { showCamera = true } label: {
                            attachLabel("camera.fill", "Take photo")
                        }
                        .buttonStyle(.plain)
                    }
                    #endif
                    PhotosPicker(selection: $receiptItem, matching: .images) {
                        attachLabel("paperclip", "Attach receipt")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text).font(.caption.weight(.bold)).tracking(1)
            .foregroundStyle(Theme.textTertiary)
    }

    private func attachLabel(_ icon: String, _ text: String) -> some View {
        HStack {
            Image(systemName: icon)
            Text(text)
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(Theme.textSecondary)
        .frame(maxWidth: .infinity).padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusSmall)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [6, 4]))
                .foregroundStyle(Theme.divider)
        )
    }

    // MARK: - Logic

    private func prefill() {
        guard let exp = editingExpense else { return }
        title = exp.title
        amountText = String(format: "%.2f", exp.amount)
        selectedCurrencyCode = exp.currencyCode
        selectedCategoryID = exp.categoryID
        date = exp.date
        notes = exp.notes
        isRecurring = exp.isRecurring
        paymentMethod = exp.paymentMethod ?? "Cash"
        if let data = exp.receiptAssetData {
            receiptData = data
            #if os(macOS)
            if let ns = NSImage(data: data) { receiptImage = Image(nsImage: ns) }
            #else
            if let ui = UIImage(data: data) { receiptImage = Image(uiImage: ui) }
            #endif
        }
    }

    private func save() {
        guard let amount = Double(amountText), amount > 0 else { return }
        isSaving = true
        Task {
            let expense = Expense(
                id: editingExpense?.id ?? UUID().uuidString,
                title: title,
                amount: amount,
                currencyCode: selectedCurrencyCode,
                categoryID: selectedCategoryID,
                date: date,
                notes: notes,
                receiptAssetData: receiptData,
                isRecurring: isRecurring,
                paymentMethod: paymentMethod
            )
            if isEditing {
                await vm.updateExpense(expense)
            } else {
                await vm.addExpense(expense)
                if isRecurring {
                    let recurring = RecurringExpense(
                        title: title, amount: amount, currencyCode: selectedCurrencyCode,
                        categoryID: selectedCategoryID, frequency: recurringFrequency,
                        startDate: date, notes: notes)
                    await vm.addRecurringExpense(recurring)
                }
            }
            isSaving = false
            dismiss()
        }
    }

    private func loadReceipt(from item: PhotosPickerItem?) async {
        guard let item else { return }
        if let data = try? await item.loadTransferable(type: Data.self) {
            #if os(macOS)
            receiptData = data
            if let ns = NSImage(data: data) { receiptImage = Image(nsImage: ns) }
            await scanReceipt(data)
            #else
            if let ui = UIImage(data: data) { setReceipt(ui) } else { receiptData = data }
            #endif
        }
    }

    #if os(iOS)
    /// Downscales + JPEG-compresses before storing — receipts live base64-encoded
    /// inside the JSON store, so raw camera output would bloat it badly.
    private func setReceipt(_ image: UIImage) {
        let resized = image.resizedForReceipt(maxDimension: 1600)
        if let data = resized.jpegData(compressionQuality: 0.6) {
            receiptData = data
            receiptImage = Image(uiImage: resized)
            Task { await scanReceipt(data) }
        }
    }
    #endif

    // MARK: - Receipt OCR (on-device, Vision)

    /// Recognizes text in the receipt: extracts the most likely total and the
    /// merchant name. The total fills the amount field if it's empty (otherwise a
    /// "Use" chip is offered); the merchant fills an empty title, which in turn
    /// triggers merchant-memory auto-categorization.
    private func scanReceipt(_ data: Data) async {
        detectedAmount = nil
        let scan = await Task.detached(priority: .userInitiated) {
            receiptScan(in: data)
        }.value
        if let amount = scan.total {
            detectedAmount = amount
            if amountText.trimmingCharacters(in: .whitespaces).isEmpty {
                amountText = String(format: "%.2f", amount)
            }
        }
        if let merchant = scan.merchant,
           title.trimmingCharacters(in: .whitespaces).isEmpty {
            title = merchant
        }
    }

    /// Auto-selects the remembered category for a known merchant — but never
    /// overrides an explicit user choice, and never while editing an expense.
    private func applyMerchantMemory(_ newTitle: String) {
        guard !isEditing, !userPickedCategory else { return }
        guard let catID = CloudKitManager.shared.categoryForMerchant(newTitle),
              vm.categories.contains(where: { $0.id == catID }) else { return }
        selectedCategoryID = catID
    }

    private func formattedDetected(_ value: Double) -> String {
        let currency = Currency.all.first { $0.code == selectedCurrencyCode } ?? .usd
        return currency.format(value)
    }
}

// MARK: - Receipt extraction (Vision OCR + heuristics)

/// Runs on-device text recognition and returns:
/// - total: the largest amount on a line mentioning total/amount/balance/due,
///   falling back to the largest amount anywhere;
/// - merchant: the topmost mostly-letters line of the receipt (store name).
private func receiptScan(in data: Data) -> (total: Double?, merchant: String?) {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return (nil, nil) }

    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = false
    try? VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
    guard let observations = request.results, !observations.isEmpty else { return (nil, nil) }

    let keywords = ["total", "amount", "balance", "due"]
    var onKeywordLines: [Double] = []
    var everywhere: [Double] = []

    for observation in observations {
        guard let line = observation.topCandidates(1).first?.string else { continue }
        let amounts = monetaryAmounts(in: line)
        guard !amounts.isEmpty else { continue }
        everywhere.append(contentsOf: amounts)
        let lower = line.lowercased()
        if keywords.contains(where: lower.contains) {
            onKeywordLines.append(contentsOf: amounts)
        }
    }
    let total = onKeywordLines.max() ?? everywhere.max()

    // Merchant: scan lines top-down (Vision's y-axis is bottom-up) and take the
    // first one that reads like a name — mostly letters, no amounts.
    var merchant: String? = nil
    let topDown = observations.sorted { $0.boundingBox.maxY > $1.boundingBox.maxY }
    for observation in topDown.prefix(5) {
        guard let line = observation.topCandidates(1).first?.string else { continue }
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let letters = trimmed.filter(\.isLetter).count
        let digits = trimmed.filter(\.isNumber).count
        guard letters >= 3, letters > digits, monetaryAmounts(in: trimmed).isEmpty else { continue }
        merchant = trimmed.capitalized
        break
    }
    return (total, merchant)
}

/// Extracts monetary values like 23.45, 1,234.56 or 1.234,56 from a line.
private func monetaryAmounts(in line: String) -> [Double] {
    let pattern = #"(\d+(?:[.,]\d{3})*[.,]\d{2})"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    let ns = line as NSString
    let matches = regex.matches(in: line, range: NSRange(location: 0, length: ns.length))
    return matches.compactMap { match in
        let raw = ns.substring(with: match.range(at: 1))
        // The last separator is the decimal point; everything else is grouping.
        guard let lastSep = raw.lastIndex(where: { $0 == "." || $0 == "," }) else { return Double(raw) }
        let decimals = raw[raw.index(after: lastSep)...]
        let integer = raw[..<lastSep]
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: ".", with: "")
        return Double("\(integer).\(decimals)")
    }
}

#if os(iOS)
// MARK: - Camera capture (receipts)

struct CameraPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    var onImage: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.isPresented = false
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.isPresented = false
        }
    }
}

private extension UIImage {
    func resizedForReceipt(maxDimension: CGFloat) -> UIImage {
        let largest = max(size.width, size.height)
        guard largest > maxDimension else { return self }
        let scale = maxDimension / largest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}
#endif
