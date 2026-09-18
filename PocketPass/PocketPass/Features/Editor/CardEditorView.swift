import SwiftUI

/// Add or edit a card. Validation is live, because a pass that fails at the till is worse
/// than one that refuses to save.
struct CardEditorView: View {
    @State var draft: CardDraft

    @EnvironmentObject private var store: CardStore
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @FocusState private var isPayloadFocused: Bool
    @State private var saveFailure: String?

    var body: some View {
        NavigationStack {
            Form {
                codeSection
                previewSection
                detailsSection
                appearanceSection
                notesSection
            }
            .navigationTitle(draft.isEditingExistingCard ? "Edit Card" : "New Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!draft.canSave)
                }
            }
            .alert("Couldn’t Save", isPresented: Binding(
                get: { saveFailure != nil },
                set: { if !$0 { saveFailure = nil } }
            )) {
                Button("OK", role: .cancel) { saveFailure = nil }
            } message: {
                Text(saveFailure ?? "")
            }
        }
    }

    // MARK: - Sections

    private var codeSection: some View {
        Section {
            TextField("Code", text: $draft.payload, axis: .vertical)
                .lineLimit(1...4)
                .font(.system(.body, design: .monospaced))
                .textInputAutocapitalization(draft.symbology == .code39 ? .characters : .never)
                .autocorrectionDisabled()
                .keyboardType(draft.symbology.isNumericOnly ? .numberPad : .default)
                .focused($isPayloadFocused)

            Picker("Format", selection: $draft.symbology) {
                ForEach(orderedSymbologies) { symbology in
                    Text(symbology.displayName).tag(symbology)
                }
            }
        } header: {
            Text("Code")
        } footer: {
            if let error = draft.payloadError, !draft.payload.isEmpty {
                Text(error.errorDescription ?? "")
                    .foregroundStyle(.red)
            } else {
                Text(draft.symbology.usageHint)
            }
        }
    }

    @ViewBuilder
    private var previewSection: some View {
        if draft.canSave {
            Section("Preview") {
                BarcodeView(payload: draft.payload, symbology: draft.symbology)
                    .padding(.vertical, 6)
                    .listRowBackground(Color.clear)
            }
        }
    }

    private var detailsSection: some View {
        Section("Details") {
            TextField("Name, e.g. Clubcard", text: $draft.name)
            TextField("Issuer, e.g. Tesco", text: $draft.organization)

            Picker("Category", selection: $draft.category) {
                ForEach(CardCategory.allCases) { category in
                    Label(category.displayName, systemImage: category.symbolName).tag(category)
                }
            }
            .onChange(of: draft.category) { oldValue, newValue in
                // Only steer the format for a card that has not been given a code yet.
                if draft.payload.isEmpty, draft.symbology == oldValue.defaultSymbology {
                    draft.symbology = newValue.defaultSymbology
                }
            }

            Toggle("Favourite", isOn: $draft.isFavorite)

            Toggle("Has an expiry date", isOn: $draft.hasExpiration.animation())
            if draft.hasExpiration {
                DatePicker(
                    "Expires",
                    selection: $draft.expirationDate,
                    displayedComponents: .date
                )
            }
        }
    }

    private var appearanceSection: some View {
        Section("Colour") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 12)], spacing: 12) {
                ForEach(CardTheme.allCases) { theme in
                    Button {
                        draft.theme = theme
                        Haptics.selection(enabled: settings.hapticsEnabled)
                    } label: {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(theme.gradient)
                            .frame(height: 44)
                            .overlay {
                                if draft.theme == theme {
                                    Image(systemName: "checkmark")
                                        .font(.headline)
                                        .foregroundStyle(.white)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(theme.displayName)
                    .accessibilityAddTraits(draft.theme == theme ? [.isSelected] : [])
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var notesSection: some View {
        Section {
            TextField("Notes, e.g. seat 14A", text: $draft.notes, axis: .vertical)
                .lineLimit(2...6)
        } header: {
            Text("Notes")
        } footer: {
            Text("Cards are stored on this device only. Nothing is uploaded.")
        }
    }

    /// Everyday formats first, the rest after, so the menu is not a lesson in barcode history.
    private var orderedSymbologies: [BarcodeSymbology] {
        BarcodeSymbology.commonlyUsed
            + BarcodeSymbology.allCases.filter { !BarcodeSymbology.commonlyUsed.contains($0) }
    }

    // MARK: - Actions

    private func save() {
        do {
            let card = try draft.makeCard()
            if draft.isEditingExistingCard {
                store.update(card)
            } else {
                store.add(card)
            }
            Haptics.success(enabled: settings.hapticsEnabled)
            dismiss()
        } catch let error as BarcodeError {
            saveFailure = error.errorDescription
        } catch {
            saveFailure = error.localizedDescription
        }
    }
}

#Preview("New") {
    CardEditorView(draft: CardDraft(theme: .ocean))
        .environmentObject(CardStore(repository: InMemoryCardRepository()))
        .environmentObject(AppSettings())
}

#Preview("Edit") {
    CardEditorView(draft: CardDraft(card: WalletCard.samples[0]))
        .environmentObject(CardStore(repository: InMemoryCardRepository(cards: WalletCard.samples)))
        .environmentObject(AppSettings())
}
