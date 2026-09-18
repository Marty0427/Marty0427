import SwiftUI

/// Decides between the lock screen and the wallet.
struct RootView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var lock: AppLockController

    var body: some View {
        Group {
            if settings.requiresUnlock && !lock.isUnlocked {
                LockScreen()
            } else {
                WalletView()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: lock.isUnlocked)
    }
}

/// Shown while the wallet is locked. Deliberately holds no card data at all.
struct LockScreen: View {
    @EnvironmentObject private var lock: AppLockController

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "lock.fill")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("PocketPass is locked")
                    .font(.title2.weight(.semibold))
                Text("Unlock with \(lock.biometryDisplayName) to see your cards.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let failureMessage = lock.failureMessage {
                Text(failureMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button {
                Task { await lock.authenticate() }
            } label: {
                Label("Unlock", systemImage: "faceid")
                    .frame(maxWidth: 220)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(lock.isAuthenticating)

            Spacer()
        }
        .padding(32)
        .task {
            // Prompt straight away; people expect the sheet, not a button to press first.
            await lock.authenticate()
        }
    }
}

#Preview {
    LockScreen()
        .environmentObject(AppLockController())
}
