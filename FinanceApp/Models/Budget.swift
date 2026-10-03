import Foundation

struct Budget: Identifiable, Codable, Hashable {
    var id: String
    var categoryID: String
    var limitAmount: Double
    var currencyCode: String
    var month: Int
    var year: Int

    init(
        id: String = UUID().uuidString,
        categoryID: String,
        limitAmount: Double,
        currencyCode: String = "USD",
        month: Int = Calendar.current.component(.month, from: Date()),
        year: Int = Calendar.current.component(.year, from: Date())
    ) {
        self.id = id
        self.categoryID = categoryID
        self.limitAmount = limitAmount
        self.currencyCode = currencyCode
        self.month = month
        self.year = year
    }

    var currency: Currency {
        Currency.all.first { $0.code == currencyCode } ?? .usd
    }

    var periodLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        var components = DateComponents()
        components.month = month
        components.year = year
        let date = Calendar.current.date(from: components) ?? Date()
        return formatter.string(from: date)
    }
}
