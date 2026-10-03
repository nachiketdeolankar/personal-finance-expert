import Foundation
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct ExpenseCategory: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var iconName: String       // SF Symbol name
    var colorHex: String
    var isSystem: Bool         // system categories cannot be deleted

    var color: Color {
        Color(hex: colorHex) ?? .blue
    }

    static let prebuilt: [ExpenseCategory] = [
        ExpenseCategory(id: "food",          name: "Food & Dining",     iconName: "fork.knife",           colorHex: "#FF6B6B", isSystem: true),
        ExpenseCategory(id: "transport",     name: "Transport",         iconName: "car.fill",             colorHex: "#4ECDC4", isSystem: true),
        ExpenseCategory(id: "shopping",      name: "Shopping",          iconName: "bag.fill",             colorHex: "#45B7D1", isSystem: true),
        ExpenseCategory(id: "housing",       name: "Housing",           iconName: "house.fill",           colorHex: "#96CEB4", isSystem: true),
        ExpenseCategory(id: "health",        name: "Health",            iconName: "heart.fill",           colorHex: "#FF6B9D", isSystem: true),
        ExpenseCategory(id: "entertainment", name: "Entertainment",     iconName: "tv.fill",              colorHex: "#C44569", isSystem: true),
        ExpenseCategory(id: "travel",        name: "Travel",            iconName: "airplane",             colorHex: "#F8B500", isSystem: true),
        ExpenseCategory(id: "education",     name: "Education",         iconName: "book.fill",            colorHex: "#6C5CE7", isSystem: true),
        ExpenseCategory(id: "utilities",     name: "Utilities",         iconName: "bolt.fill",            colorHex: "#FDCB6E", isSystem: true),
        ExpenseCategory(id: "subscriptions", name: "Subscriptions",     iconName: "repeat",               colorHex: "#74B9FF", isSystem: true),
        ExpenseCategory(id: "personal",      name: "Personal Care",     iconName: "person.fill",          colorHex: "#A29BFE", isSystem: true),
        ExpenseCategory(id: "groceries",     name: "Groceries",         iconName: "cart.fill",            colorHex: "#55EFC4", isSystem: true),
        ExpenseCategory(id: "other",         name: "Other",             iconName: "ellipsis.circle.fill", colorHex: "#B2BEC3", isSystem: true),
    ]
}

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }

    var hexString: String {
        #if os(macOS)
        let nsColor = NSColor(self).usingColorSpace(.deviceRGB) ?? .black
        let r = Int(nsColor.redComponent * 255)
        let g = Int(nsColor.greenComponent * 255)
        let b = Int(nsColor.blueComponent * 255)
        #else
        var rf: CGFloat = 0, gf: CGFloat = 0, bf: CGFloat = 0, af: CGFloat = 0
        UIColor(self).getRed(&rf, green: &gf, blue: &bf, alpha: &af)
        let r = Int(rf * 255)
        let g = Int(gf * 255)
        let b = Int(bf * 255)
        #endif
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

// MARK: - Dynamic (light/dark adaptive) Color

extension Color {
    /// Builds a color that automatically switches with the system appearance.
    init(light: Color, dark: Color) {
        #if os(macOS)
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(isDark ? dark : light)
        })
        #else
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
        #endif
    }

    init(lightHex: String, darkHex: String) {
        self.init(light: Color(hex: lightHex) ?? .gray, dark: Color(hex: darkHex) ?? .gray)
    }
}

// MARK: - Theme palette (Midnight + adaptive light)

enum Theme {
    // Brand — Graphite (slate in light, silver in dark)
    static let accent     = Color(lightHex: "#3A3F4B", darkHex: "#C7CDD8")
    static let accentSoft = Color(light: Color(hex: "#3A3F4B")!.opacity(0.14),
                                  dark:  Color(hex: "#C7CDD8")!.opacity(0.18))
    static let accentGradient = LinearGradient(
        colors: [accent, accent.opacity(0.82)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
    static let onAccent = Color(light: Color(hex: "#F2F3F5")!, dark: Color(hex: "#20242C")!)

    // Surfaces
    static let background        = Color(lightHex: "#F4F4F7", darkHex: "#0A0B0D")
    static let groupedBackground = Color(lightHex: "#F4F4F7", darkHex: "#0A0B0D")
    static let card              = Color(lightHex: "#FFFFFF", darkHex: "#141518")
    static let cardElevated      = Color(lightHex: "#FFFFFF", darkHex: "#1C1E22")
    static let chip              = Color(lightHex: "#FFFFFF", darkHex: "#1C1E22")
    static let fill              = Color(lightHex: "#ECECF1", darkHex: "#1C1E22")

    // Text
    static let textPrimary   = Color(lightHex: "#15161A", darkHex: "#F5F7F8")
    static let textSecondary = Color(lightHex: "#3A3A3C", darkHex: "#A0A4AD")
    static let textTertiary  = Color(lightHex: "#8E8E93", darkHex: "#6B7078")

    // Lines & tracks
    static let divider = Color(light: .black.opacity(0.06), dark: .white.opacity(0.07))
    static let track   = Color(lightHex: "#E5E5EA", darkHex: "#23252B")

    // Status / trend
    static let warn      = Color(hex: "#FF9F0A")!
    static let danger    = Color(hex: "#FF5A5F")!
    static let ok        = accent
    static let upTrend   = Color(hex: "#FF5A5F")!   // spending increased (bad)
    static let downTrend = accent                    // spending decreased (good)

    // Layout
    static let radius: CGFloat      = 20
    static let radiusSmall: CGFloat = 14
    static let cardPadding: CGFloat = 18
    static let spacing: CGFloat     = 16

    // Typography (Direction C: serif money figures, monospaced micro-labels)
    /// Serif display font for money figures (New York).
    static func figure(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
    /// Monospaced font for uppercase micro-labels (SF Mono).
    static func label(_ size: CGFloat = 11) -> Font {
        .system(size: size, weight: .medium, design: .monospaced)
    }
}

// MARK: - Reusable card container

struct ThemedCard<Content: View>: View {
    var title: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title {
                Text(title.uppercased())
                    .monoLabel()
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.cardPadding)
        .glassCard()
    }
}

// MARK: - Liquid Glass helpers (iOS 26 / macOS 26)

extension View {
    /// Uppercase monospaced micro-label (Origin-style structure marker).
    func monoLabel(_ size: CGFloat = 11) -> some View {
        self
            .font(Theme.label(size))
            .tracking(1.4)
            .foregroundStyle(Theme.textTertiary)
    }
    /// Opaque content surface. Per Apple's guidance, the content layer stays solid —
    /// Liquid Glass is reserved for the control layer (nav bar, FABs, segmented controls).
    func glassCard(_ radius: CGFloat = Theme.radius) -> some View {
        self
            .background(Theme.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Theme.divider, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.06), radius: 8, y: 2)
    }
    /// Accent-tinted interactive glass in a rounded rectangle (control layer).
    func glassAccentCard(_ radius: CGFloat) -> some View {
        glassEffect(.regular.tint(Theme.accent).interactive(),
                    in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

