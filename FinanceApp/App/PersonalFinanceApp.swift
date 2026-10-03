import SwiftUI

@main
struct PersonalFinanceApp: App {
    @StateObject private var authManager = AuthenticationManager.shared
    @StateObject private var ckManager   = CloudKitManager.shared
    @StateObject private var vm          = ExpenseViewModel()
    @StateObject private var storage     = StorageManager.shared

    var body: some Scene {
        #if os(macOS)
        WindowGroup {
            contentView
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        #else
        WindowGroup {
            contentView
        }
        #endif
    }

    @ViewBuilder
    private var contentView: some View {
        Group {
            if authManager.authState != .authenticated {
                LockScreenView()
            } else if !storage.hasChosen {
                StorageSetupView()
            } else {
                MainNavigationView()
                    .overlay(alignment: .top) {
                        if let err = vm.error {
                            ErrorBanner(message: err) { vm.error = nil }
                        }
                        if ckManager.isSyncing {
                            SyncIndicator()
                        }
                    }
            }
        }
        .tint(Theme.accent)
        .environmentObject(authManager)
        .environmentObject(ckManager)
        .environmentObject(vm)
        .environmentObject(storage)
        .task { await ckManager.checkAccountStatus() }
        .task { await ckManager.setupSubscriptions() }
        // No background locking: switching apps keeps the session and the current tab.
        // Face ID is required only on a cold launch, because AuthenticationManager starts
        // in the .locked state when the process is created (e.g. after the app is killed).
    }
}

// MARK: - Support Views

struct ErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(2)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.spring(response: 0.3), value: message)
    }
}

struct SyncIndicator: View {
    var body: some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.mini)
            Text("Syncing…").font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.thinMaterial, in: Capsule())
        .padding(.top, 8)
    }
}
