import SwiftUI
import LocalAuthentication

struct LockScreenView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var pin: String = ""
    @State private var showPINEntry: Bool = false
    @State private var pinError: String?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 48) {
                Spacer()

                // App Icon + Name
                VStack(spacing: 18) {
                    ZStack {
                        Circle().fill(Theme.accentSoft).frame(width: 112, height: 112)
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 46, weight: .regular))
                            .foregroundStyle(Theme.accent)
                    }

                    Text("Personal Finance Expert")
                        .font(.title2).fontWeight(.bold)
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.center)

                    Text("Your financial data is locked.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }

                Spacer()

                if showPINEntry || authManager.authState == .biometricUnavailable {
                    pinEntryView
                } else {
                    biometricButton
                }

                Spacer()
            }
            .padding(32)
        }
        .task { await authManager.authenticate() }
    }

    // MARK: - Biometric Button

    private var biometricButton: some View {
        VStack(spacing: 20) {
            Button {
                Task { await authManager.authenticate() }
            } label: {
                Label("Unlock with \(authManager.biometricLabel)", systemImage: authManager.biometricIcon)
                    .font(.headline)
                    .frame(maxWidth: 240)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)

            if authManager.isPINSetup {
                Button("Use PIN instead") {
                    showPINEntry = true
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            if let err = authManager.authError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - PIN Entry

    private var pinEntryView: some View {
        VStack(spacing: 24) {
            Text("Enter PIN")
                .font(.headline)

            // PIN dots
            HStack(spacing: 16) {
                ForEach(0..<6, id: \.self) { idx in
                    Circle()
                        .fill(idx < pin.count ? Color.primary : Color.secondary.opacity(0.3))
                        .frame(width: 14, height: 14)
                }
            }

            if let err = pinError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            // Numpad
            numpadView

            if authManager.biometricType != .none {
                Button("Use \(authManager.biometricLabel)") {
                    showPINEntry = false
                    pinError = nil
                    pin = ""
                    Task { await authManager.authenticate() }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var numpadView: some View {
        VStack(spacing: 12) {
            ForEach([[1, 2, 3], [4, 5, 6], [7, 8, 9], [0]], id: \.self) { row in
                HStack(spacing: 12) {
                    ForEach(row, id: \.self) { digit in
                        numpadButton(digit: digit)
                    }
                    if row == [0] {
                        numpadDeleteButton
                    }
                }
            }
        }
    }

    private func numpadButton(digit: Int) -> some View {
        Button {
            guard pin.count < 6 else { return }
            pin.append(Character("\(digit)"))
            if pin.count == 6 { verifyPIN() }
        } label: {
            Text("\(digit)")
                .font(.title2)
                .frame(width: 72, height: 72)
                .background(.regularMaterial, in: Circle())
        }
        .buttonStyle(.plain)
    }

    private var numpadDeleteButton: some View {
        Button {
            guard !pin.isEmpty else { return }
            pin.removeLast()
        } label: {
            Image(systemName: "delete.left")
                .font(.title2)
                .frame(width: 72, height: 72)
                .background(.regularMaterial, in: Circle())
        }
        .buttonStyle(.plain)
    }

    private func verifyPIN() {
        if authManager.verifyPIN(pin) {
            pinError = nil
        } else {
            pinError = "Incorrect PIN. Try again."
            pin = ""
        }
    }
}
