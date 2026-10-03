import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var ckManager: CloudKitManager
    @EnvironmentObject var storage: StorageManager
    @EnvironmentObject var vm: ExpenseViewModel
    @AppStorage("defaultCurrencyCode") var defaultCurrencyCode: String = "USD"
    @AppStorage("syncMode") var syncMode: String = AppSettings.SyncMode.realtime.rawValue
    @AppStorage("budgetAlertThreshold") var budgetAlertThreshold: Double = 0.8
    @AppStorage(RecurringReminders.enabledKey) var recurringReminders: Bool = false
    @AppStorage("widgetMaskAmounts") var widgetMaskAmounts: Bool = false

    @State private var showCurrencyPicker: Bool = false
    @State private var showPINSetup: Bool = false
    @State private var showPINChange: Bool = false
    @State private var showFolderPicker: Bool = false
    @State private var storageError: String?
    @State private var showClearConfirm: Bool = false

    var body: some View {
        Form {
            // iCloud Status
            Section {
                HStack {
                    Label("Location", systemImage: "externaldrive.fill")
                    Spacer()
                    Text(storage.locationDescription)
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
                Button("Use This Device") {
                    storage.chooseLocal()
                    Task { await vm.loadAll() }
                }
                Button("Sync via iCloud Drive Folder…") { showFolderPicker = true }
                if let storageError {
                    Text(storageError).font(.caption).foregroundStyle(.red)
                }
            } header: {
                Text("Storage")
            } footer: {
                Text("iCloud Drive sync is file-based and updates within a few moments. Pick the same folder on each device.")
            }

            // Security
            Section {
                HStack {
                    Label(authManager.biometricLabel, systemImage: authManager.biometricIcon)
                    Spacer()
                    Text("Enabled").foregroundStyle(.secondary).font(.subheadline)
                }

                if authManager.isPINSetup {
                    Button("Change PIN") { showPINChange = true }
                    Button("Remove PIN", role: .destructive) { authManager.removePIN() }
                } else {
                    Button("Set Up PIN Fallback") { showPINSetup = true }
                }
            } header: {
                Text("Security")
            } footer: {
                Text("\(authManager.biometricLabel) is required when you open the app. Switching to another app and back keeps you signed in — only fully closing the app will require \(authManager.biometricLabel) again.")
            }

            // Preferences
            Section("Preferences") {
                Button {
                    showCurrencyPicker = true
                } label: {
                    HStack {
                        Label("Default Currency", systemImage: "dollarsign.circle.fill")
                        Spacer()
                        Text(defaultCurrencyCode)
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .foregroundStyle(.primary)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label("Budget Alert", systemImage: "bell.fill")
                        Spacer()
                        Text("\(Int(budgetAlertThreshold * 100))%")
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $budgetAlertThreshold, in: 0.5...1.0, step: 0.05)
                        .tint(.orange)
                }

                Toggle(isOn: $recurringReminders) {
                    Label("Recurring Reminders", systemImage: "bell.badge.fill")
                }
                .onChange(of: recurringReminders) { _, enabled in
                    Task {
                        if enabled {
                            let granted = await RecurringReminders.shared.requestPermission()
                            if !granted { recurringReminders = false; return }
                        }
                        RecurringReminders.shared.reschedule(for: vm.recurringExpenses)
                    }
                }

                Toggle(isOn: $widgetMaskAmounts) {
                    Label("Mask Amounts in Widgets", systemImage: "eye.slash.fill")
                }
                .onChange(of: widgetMaskAmounts) { _, _ in
                    Task { await ckManager.refreshWidgetSnapshot() }
                }
            }

            // Data
            Section {
                NavigationLink {
                    ExportView()
                } label: {
                    Label("Export Data…", systemImage: "square.and.arrow.up")
                }
                Button("Clear All Data", role: .destructive) { showClearConfirm = true }
            } header: {
                Text("Data")
            } footer: {
                Text("Removes all expenses, budgets, recurring items and custom categories from the current storage location.")
            }

            // About
            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("1.1.0").foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog("Clear all data?", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("Clear All Data", role: .destructive) { vm.clearAllData() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes all expenses, budgets, recurring items and custom categories. This cannot be undone.")
        }
        .fileImporter(isPresented: $showFolderPicker, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    do {
                        try storage.chooseFolder(url); storageError = nil
                        Task { await vm.loadAll() }
                    }
                    catch { storageError = error.localizedDescription }
                }
            case .failure(let err):
                storageError = err.localizedDescription
            }
        }
        .sheet(isPresented: $showCurrencyPicker) {
            CurrencyPickerView(selectedCode: $defaultCurrencyCode)
        }
        .sheet(isPresented: $showPINSetup) {
            PINSetupView(mode: .setup)
        }
        .sheet(isPresented: $showPINChange) {
            PINSetupView(mode: .change)
        }
    }

}

// MARK: - PIN Setup

struct PINSetupView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.dismiss) private var dismiss

    enum Mode { case setup, change }
    let mode: Mode

    @State private var pin: String = ""
    @State private var confirmPin: String = ""
    @State private var step: Int = 1   // 1 = enter, 2 = confirm
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                VStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 44, weight: .thin))
                    Text(step == 1 ? "Enter a 6-digit PIN" : "Confirm your PIN")
                        .font(.title3)
                        .fontWeight(.semibold)
                    if let err = error {
                        Text(err).font(.caption).foregroundStyle(.red)
                    }
                }

                // Dots
                HStack(spacing: 16) {
                    ForEach(0..<6, id: \.self) { idx in
                        Circle()
                            .fill(idx < currentEntry.count ? Color.primary : Color.secondary.opacity(0.3))
                            .frame(width: 14, height: 14)
                    }
                }

                // Numpad
                VStack(spacing: 12) {
                    ForEach([[1, 2, 3], [4, 5, 6], [7, 8, 9], [0]], id: \.self) { row in
                        HStack(spacing: 12) {
                            ForEach(row, id: \.self) { digit in
                                Button {
                                    appendDigit(digit)
                                } label: {
                                    Text("\(digit)")
                                        .font(.title2)
                                        .frame(width: 72, height: 72)
                                        .background(.regularMaterial, in: Circle())
                                }
                                .buttonStyle(.plain)
                            }
                            if row == [0] {
                                Button {
                                    if !currentEntry.isEmpty {
                                        if step == 1 { pin.removeLast() } else { confirmPin.removeLast() }
                                    }
                                } label: {
                                    Image(systemName: "delete.left")
                                        .font(.title2)
                                        .frame(width: 72, height: 72)
                                        .background(.regularMaterial, in: Circle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                Spacer()
            }
            .navigationTitle(mode == .setup ? "Set PIN" : "Change PIN")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
    }

    private var currentEntry: String { step == 1 ? pin : confirmPin }

    private func appendDigit(_ digit: Int) {
        error = nil
        if step == 1 {
            guard pin.count < 6 else { return }
            pin.append(Character("\(digit)"))
            if pin.count == 6 { step = 2 }
        } else {
            guard confirmPin.count < 6 else { return }
            confirmPin.append(Character("\(digit)"))
            if confirmPin.count == 6 { finalize() }
        }
    }

    private func finalize() {
        if pin == confirmPin {
            _ = authManager.setupPIN(pin)
            dismiss()
        } else {
            error = "PINs don't match. Try again."
            pin = ""
            confirmPin = ""
            step = 1
        }
    }
}

// MARK: - First-boot storage picker

struct StorageSetupView: View {
    @EnvironmentObject var storage: StorageManager
    @State private var showFolderPicker = false
    @State private var pickError: String?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 22) {
                    VStack(spacing: 12) {
                        Image(systemName: "externaldrive.badge.icloud")
                            .font(.system(size: 50, weight: .thin))
                            .foregroundStyle(Theme.accent)
                        Text("Where should we keep your data?")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(Theme.textPrimary)
                            .multilineTextAlignment(.center)
                        Text("You can change this anytime in Settings.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.top, 30)

                    optionCard(icon: "internaldrive.fill",
                               title: "On This Device",
                               subtitle: "Private to this device. Fast and simple — no syncing.") {
                        storage.chooseLocal()
                    }

                    optionCard(icon: "icloud.fill",
                               title: "Sync via iCloud Drive",
                               subtitle: "Pick a folder in iCloud Drive. Your data syncs across your devices automatically. Choose the same folder on each device.") {
                        showFolderPicker = true
                    }

                    if let pickError {
                        Text(pickError).font(.caption).foregroundStyle(Theme.danger)
                    }

                    Text("iCloud Drive sync is file-based and may take a moment to update. Avoid editing on two devices at the exact same time.")
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(20)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
        }
        .fileImporter(isPresented: $showFolderPicker, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    do { try storage.chooseFolder(url) }
                    catch { pickError = "Couldn't use that folder: \(error.localizedDescription)" }
                }
            case .failure(let err):
                pickError = err.localizedDescription
            }
        }
    }

    private func optionCard(icon: String, title: String, subtitle: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Theme.accentSoft).frame(width: 50, height: 50)
                    Image(systemName: icon).font(.system(size: 22)).foregroundStyle(Theme.accent)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline).foregroundStyle(Theme.textPrimary)
                    Text(subtitle).font(.caption).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Theme.textTertiary)
            }
            .padding(16)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .strokeBorder(Theme.divider, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}
