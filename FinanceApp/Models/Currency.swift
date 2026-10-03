import Foundation

struct Currency: Codable, Identifiable, Hashable {
    var id: String { code }
    let code: String
    let name: String
    let symbol: String

    static let all: [Currency] = [
        Currency(code: "USD", name: "US Dollar", symbol: "$"),
        Currency(code: "EUR", name: "Euro", symbol: "€"),
        Currency(code: "GBP", name: "British Pound", symbol: "£"),
        Currency(code: "JPY", name: "Japanese Yen", symbol: "¥"),
        Currency(code: "INR", name: "Indian Rupee", symbol: "₹"),
        Currency(code: "CAD", name: "Canadian Dollar", symbol: "CA$"),
        Currency(code: "AUD", name: "Australian Dollar", symbol: "A$"),
        Currency(code: "CHF", name: "Swiss Franc", symbol: "CHF"),
        Currency(code: "CNY", name: "Chinese Yuan", symbol: "¥"),
        Currency(code: "SGD", name: "Singapore Dollar", symbol: "S$"),
        Currency(code: "AED", name: "UAE Dirham", symbol: "د.إ"),
        Currency(code: "MXN", name: "Mexican Peso", symbol: "$"),
        Currency(code: "BRL", name: "Brazilian Real", symbol: "R$"),
        Currency(code: "KRW", name: "South Korean Won", symbol: "₩"),
        Currency(code: "HKD", name: "Hong Kong Dollar", symbol: "HK$"),
        Currency(code: "SEK", name: "Swedish Krona", symbol: "kr"),
        Currency(code: "NOK", name: "Norwegian Krone", symbol: "kr"),
        Currency(code: "NZD", name: "New Zealand Dollar", symbol: "NZ$"),
        Currency(code: "ZAR", name: "South African Rand", symbol: "R"),
        Currency(code: "THB", name: "Thai Baht", symbol: "฿"),
    ]

    static let usd = Currency(code: "USD", name: "US Dollar", symbol: "$")

    func format(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        formatter.currencySymbol = symbol
        return formatter.string(from: NSNumber(value: amount)) ?? "\(symbol)\(amount)"
    }
}
