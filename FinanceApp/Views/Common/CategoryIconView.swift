import SwiftUI

struct CategoryIconView: View {
    let category: ExpenseCategory
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(category.color.opacity(0.18))
                .frame(width: size, height: size)
            Image(systemName: category.iconName)
                .font(.system(size: size * 0.46, weight: .medium))
                .foregroundStyle(category.color)
        }
    }
}

struct CategoryBadge: View {
    let category: ExpenseCategory

    var body: some View {
        HStack(spacing: 6) {
            CategoryIconView(category: category, size: 20)
            Text(category.name)
                .font(.caption)
                .foregroundStyle(category.color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(category.color.opacity(0.12), in: Capsule())
    }
}
