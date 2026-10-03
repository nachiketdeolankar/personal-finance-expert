import SwiftUI

struct CategoryManagerView: View {
    @EnvironmentObject var vm: ExpenseViewModel
    @State private var showAddCategory: Bool = false
    @State private var deleteTarget: ExpenseCategory?

    var body: some View {
        List {
            Section("Built-in Categories") {
                ForEach(vm.categories.filter(\.isSystem)) { cat in
                    categoryRow(cat)
                }
            }

            Section("Custom Categories") {
                let custom = vm.categories.filter { !$0.isSystem }
                if custom.isEmpty {
                    Text("No custom categories yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(custom) { cat in
                        categoryRow(cat)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    deleteTarget = cat
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Categories")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showAddCategory = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddCategory) {
            AddCategoryView()
        }
        .confirmationDialog(
            "Delete \"\(deleteTarget?.name ?? "")\"?",
            isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let cat = deleteTarget {
                    Task { await vm.deleteCategory(cat) }
                }
                deleteTarget = nil
            }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: {
            Text("All expenses in this category will remain but show as uncategorized.")
        }
    }

    private func categoryRow(_ cat: ExpenseCategory) -> some View {
        HStack(spacing: 12) {
            CategoryIconView(category: cat, size: 36)
            Text(cat.name).font(.subheadline).foregroundStyle(Theme.textPrimary)
            Spacer()
            if cat.isSystem {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .listRowBackground(Theme.card)
    }
}

// MARK: - Add Category

struct AddCategoryView: View {
    @EnvironmentObject var vm: ExpenseViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var selectedIcon: String = "tag.fill"
    @State private var selectedColor: Color = .blue

    let icons = [
        "tag.fill", "star.fill", "heart.fill", "flame.fill", "bolt.fill",
        "gift.fill", "pawprint.fill", "leaf.fill", "drop.fill", "moon.fill",
        "sun.max.fill", "cloud.fill", "snowflake", "music.note", "gamecontroller.fill",
        "wrench.fill", "hammer.fill", "paintbrush.fill", "scissors", "briefcase.fill",
        "stethoscope", "pills.fill", "bandage.fill", "dumbbell.fill", "figure.run",
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Category name", text: $name)
                }

                Section("Color") {
                    ColorPicker("Pick a color", selection: $selectedColor, supportsOpacity: false)
                }

                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                        ForEach(icons, id: \.self) { icon in
                            Button {
                                selectedIcon = icon
                            } label: {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(selectedIcon == icon ? selectedColor.opacity(0.2) : Theme.fill)
                                    Image(systemName: icon)
                                        .font(.system(size: 20))
                                        .foregroundStyle(selectedIcon == icon ? selectedColor : .secondary)
                                }
                                .frame(height: 48)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Preview") {
                    let preview = ExpenseCategory(
                        id: "preview",
                        name: name.isEmpty ? "Category" : name,
                        iconName: selectedIcon,
                        colorHex: selectedColor.hexString,
                        isSystem: false
                    )
                    HStack {
                        CategoryIconView(category: preview, size: 40)
                        Text(preview.name).font(.subheadline)
                    }
                }
            }
            .navigationTitle("New Category")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) {
                        let category = ExpenseCategory(
                            id: UUID().uuidString,
                            name: name,
                            iconName: selectedIcon,
                            colorHex: selectedColor.hexString,
                            isSystem: false
                        )
                        Task {
                            await vm.addCategory(category)
                            dismiss()
                        }
                    }
                    .disabled(name.isEmpty)
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
