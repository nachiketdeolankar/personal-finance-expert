import Foundation

struct Expense: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var amount: Double
    var currencyCode: String
    var categoryID: String
    var date: Date
    var notes: String
    var receiptAssetData: Data?
    var isRecurring: Bool
    var recurringID: String?
    var paymentMethod: String?     // e.g. "Cash", "•••• 4242"
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        title: String,
        amount: Double,
        currencyCode: String = "USD",
        categoryID: String = "other",
        date: Date = Date(),
        notes: String = "",
        receiptAssetData: Data? = nil,
        isRecurring: Bool = false,
        recurringID: String? = nil,
        paymentMethod: String? = nil
    ) {
        self.id = id
        self.title = title
        self.amount = amount
        self.currencyCode = currencyCode
        self.categoryID = categoryID
        self.date = date
        self.notes = notes
        self.receiptAssetData = receiptAssetData
        self.isRecurring = isRecurring
        self.recurringID = recurringID
        self.paymentMethod = paymentMethod
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var currency: Currency {
        Currency.all.first { $0.code == currencyCode } ?? .usd
    }

    var formattedAmount: String {
        currency.format(amount)
    }
}

