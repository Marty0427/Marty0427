import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var store: CardStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var lock: AppLockController
    @Environment(\.dismiss) private var dismiss

    @State private var exportURL: URL?
    @State private var isImporting = false
    @State private var message: AlertMessage?

    var body: some View {
        NavigationStack {
            Form {
                showingSection
                privacySection
                dataSection
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { prepareExport() }
            .onChange(of: store.cards) { _, _ in prepareExport() }
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                handleImport(result)
            }
            .alert(
                message?.title ?? "",
                isPresented: Binding(
                    get: { message != nil },
                    set: { if !$0 { message = nil } }
                ),
                presenting: message
            ) { _ in
                Button("OK", role: .cancel) { message = nil }
            } message: { alert in
                Text(alert.body)
            }
        }
    }

    // MARK: - Sections

    private var showingSection: some View {
        Section {
            Toggle("Brighten screen for codes", isOn: $settings.boostsBrightness)
            Toggle("Keep screen awake while showing", isOn: $settings.keepsScreenAwake)
            Toggle("Haptics", isOn: $settings.hapticsEnabled)
        } header: {
            Text("Showing a Card")
        } footer: {
            Text("Scanners at tills need a bright screen. Your usual brightness comes back when you leave the card.")
        }
    }

    private var privacySection: some View {
        Section {
            Toggle("Require \(lock.biometryDisplayName)", isOn: $settings.requiresUnlock)
                .disabled(!lock.isAvailable)
                .onChange(of: settings.requiresUnlock) { _, isOn in
                    // Turning the lock on should not immediately lock the person out of
                    // the screen they are standing on.
                    if isOn { lock.unlockWithoutAuthenticating() }
                }
        } header: {
            Text("Privacy")
        } footer: {
            if lock.isAvailable {
                Text("Asks for \(lock.biometryDisplayName) each time PocketPass opens. Your cards are also protected by iOS file encryption while the device is locked.")
            } else {
                Text("Set a device passcode to use this.")
            }
        }
    }

    private var dataSection: some View {
        Section {
            if let exportURL {
                ShareLink(item: exportURL) {
                    Label("Export Backup", systemImage: "square.and.arrow.up")
                }
            } else {
                Label("Export Backup", systemImage: "square.and.arrow.up")
                    .foregroundStyle(.secondary)
            }

            Button {
                isImporting = true
            } label: {
                Label("Restore from Backup", systemImage: "square.and.arrow.down")
            }
        } header: {
            Text("Your Data")
        } footer: {
            Text("The backup is a readable JSON file containing \(store.cards.count) card\(store.cards.count == 1 ? "" : "s"). Anyone who opens it can read the codes, so keep it somewhere safe.")
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("Version", value: Bundle.main.versionDescription)
            NavigationLink {
                PrivacyDetailView()
            } label: {
                Label("Privacy", systemImage: "hand.raised")
            }
        } header: {
            Text("About")
        }
    }

    // MARK: - Actions

    private func prepareExport() {
        exportURL = try? BackupService.writeBackup(cards: store.cards)
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let cards = try BackupService.readBackup(at: url)
                let added = store.importCards(cards, strategy: .merge)
                message = AlertMessage(
                    title: "Backup Restored",
                    body: added == 0
                        ? "Every card in that backup is already in your wallet."
                        : "Added \(added) card\(added == 1 ? "" : "s")."
                )
            } catch {
                message = AlertMessage(title: "Couldn’t Restore", body: error.localizedDescription)
            }
        case .failure(let error):
            message = AlertMessage(title: "Couldn’t Restore", body: error.localizedDescription)
        }
    }

    private struct AlertMessage: Identifiable {
        let id = UUID()
        let title: String
        let body: String
    }
}

/// Plain-language privacy statement, matching what the App Store listing declares.
struct PrivacyDetailView: View {
    var body: some View {
        List {
            Section {
                Text("PocketPass keeps every card on this device. There is no account, no server and no analytics.")
            }
            Section("Camera") {
                Text("The camera is used only while the scanner is open, to read a barcode. Frames are analysed on device and never stored or sent anywhere.")
            }
            Section("Photos") {
                Text("Importing a photo uses Apple’s photo picker, which hands PocketPass the single image you choose. The app has no access to the rest of your library.")
            }
            Section("Backups") {
                Text("An exported backup is an ordinary JSON file. Wherever you put it — AirDrop, Files, a cloud drive — is up to you, and outside the app’s control.")
            }
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension Bundle {
    var versionDescription: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

#Preview {
    SettingsView()
        .environmentObject(CardStore(repository: InMemoryCardRepository(cards: WalletCard.samples)))
        .environmentObject(AppSettings())
        .environmentObject(AppLockController())
}
