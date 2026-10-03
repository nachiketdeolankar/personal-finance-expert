import Foundation

struct AppSettings: Codable {
    var defaultCurrencyCode: String = "USD"
    var useBiometrics: Bool = true
    var fallbackPINEnabled: Bool = true
    var syncMode: SyncMode = .realtime
    var lockAfterSeconds: Int = 0   // 0 = always lock on launch
    var budgetAlertThreshold: Double = 0.8   // alert at 80% of budget

    enum SyncMode: String, Codable, CaseIterable {
        case realtime           = "Real-time"
        case backgroundPeriodic = "Background (Periodic)"
    }
}
