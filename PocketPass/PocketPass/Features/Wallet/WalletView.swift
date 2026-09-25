import SwiftUI

/// The wallet: every stored pass, searchable and filterable, with the add flows hanging off it.
struct WalletView: View {
    @EnvironmentObject private var store: CardStore
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var lock: AppLockController

    @State private var searchText = ""
    @State private var selectedCategory: CardCategory?
    @State private var draft: CardDraft?
    @State private var isShowingScanner = false
    @State private var isShowingPhotoImport = false
    @State private var isShowingSettings = false
    @State private var duplicateWarning: DuplicateWarning?

    private let columns = [GridItem(.adaptive(minimum: 320), spacing: 16)]

    var body: some View {
        NavigationStack {
            Group {
                if store.cards.isEmpty {
                    emptyWallet
                } else if visibleCards.isEmpty {
                    noMatches
                } else {
                    cardGrid
                }
            }
            .navigationTitle("Cards")
            .searchable(text: $searchText, prompt: "Search cards")
            .toolbar { toolbarContent }
            .navigationDestination(for: UUID.self) { id in
                CardDetailView(cardID: id) { card in
                    draft = CardDraft(card: card)
                }
            }
            .safeAreaInset(edge: .top) { storageErrorBanner }
        }
        .sheet(isPresented: $isShowingScanner) {
            ScannerScreen { result in
                handleScan(result)
            }
            .environmentObject(settings)
        }
        .sheet(isPresented: $isShowingPhotoImport) {
            PhotoImportScreen { result in
                handleScan(result)
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView()
                .environmentObject(store)
                .environmentObject(settings)
                .environmentObject(lock)
        }
        .sheet(item: $draft) { draft in
            CardEditorView(draft: draft)
                .environmentObject(store)
                .environmentObject(settings)
        }
        .alert(
            "Already in your wallet",
            isPresented: Binding(
                get: { duplicateWarning != nil },
                set: { if !$0 { duplicateWarning = nil } }
            ),
            presenting: duplicateWarning
        ) { warning in
            Button("Add Anyway") {
                let pending = warning.draft
                duplicateWarning = nil
                draft = pending
            }
            Button("Not Now", role: .cancel) { duplicateWarning = nil }
        } message: { warning in
            Text("“\(warning.existingName)” already holds the same code.")
        }
    }

    // MARK: - Content

    private var visibleCards: [WalletCard] {
        store.filteredCards(query: searchText, category: selectedCategory)
    }

    private var cardGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(visibleCards) { card in
                    NavigationLink(value: card.id) {
                        CardTileView(card: card)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("cardTile")
                    .contextMenu {
                        Button {
                            store.toggleFavorite(card)
                        } label: {
                            Label(
                                card.isFavorite ? "Remove Favourite" : "Add to Favourites",
                                systemImage: card.isFavorite ? "star.slash" : "star"
                            )
                        }
                        Button {
                            draft = CardDraft(card: card)
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            store.delete(card)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(16)
        }
        .safeAreaInset(edge: .top, spacing: 0) { categoryFilter }
        .background(Color(.systemGroupedBackground))
    }

    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(title: "All", systemImage: "square.grid.2x2", isSelected: selectedCategory == nil) {
                    selectedCategory = nil
                }
                ForEach(presentCategories) { category in
                    FilterChip(
                        title: category.displayName,
                        systemImage: category.symbolName,
                        isSelected: selectedCategory == category
                    ) {
                        selectedCategory = selectedCategory == category ? nil : category
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(.bar)
    }

    /// Only categories that are actually in use, so the filter row stays short.
    private var presentCategories: [CardCategory] {
        let used = Set(store.cards.map(\.category))
        return CardCategory.allCases.filter(used.contains)
    }

    private var emptyWallet: some View {
        ContentUnavailableView {
            Label("No Cards Yet", systemImage: "wallet.pass")
        } description: {
            Text("Add a loyalty card, a boarding pass or a ticket and it will be here, ready to scan — even without a signal.")
        } actions: {
            Button {
                isShowingScanner = true
            } label: {
                Label("Scan a Card", systemImage: "barcode.viewfinder")
            }
            .buttonStyle(.borderedProminent)

            Button {
                isShowingPhotoImport = true
            } label: {
                Label("Import from Photos", systemImage: "photo.on.rectangle")
            }
        }
    }

    private var noMatches: some View {
        ContentUnavailableView.search(text: searchText)
    }

    @ViewBuilder
    private var storageErrorBanner: some View {
        if let message = store.storageErrorMessage {
            Text(message)
                .font(.footnote)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.red)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                isShowingSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .accessibilityIdentifier("settingsButton")
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button {
                    isShowingScanner = true
                } label: {
                    Label("Scan Code", systemImage: "barcode.viewfinder")
                }
                Button {
                    isShowingPhotoImport = true
                } label: {
                    Label("Import from Photos", systemImage: "photo.on.rectangle")
                }
                Button {
                    draft = CardDraft(theme: store.suggestedTheme(for: .loyalty))
                } label: {
                    Label("Enter Manually", systemImage: "keyboard")
                }
            } label: {
                Label("Add Card", systemImage: "plus")
            }
            .accessibilityIdentifier("addButton")
        }
    }

    // MARK: - Actions

    private func handleScan(_ result: ScanResult) {
        let category = CardCategory.loyalty
        let newDraft = CardDraft(
            scan: result,
            theme: store.suggestedTheme(for: category)
        )

        if let existing = store.existingCard(payload: result.payload, symbology: result.symbology) {
            duplicateWarning = DuplicateWarning(existingName: existing.displayName, draft: newDraft)
        } else {
            draft = newDraft
        }
    }

    private struct DuplicateWarning: Identifiable {
        let id = UUID()
        let existingName: String
        let draft: CardDraft
    }
}

/// Pill used by the category filter row.
private struct FilterChip: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.thinMaterial),
                    in: Capsule()
                )
                .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

#Preview {
    WalletView()
        .environmentObject(CardStore(repository: InMemoryCardRepository(cards: WalletCard.samples)))
        .environmentObject(AppSettings())
        .environmentObject(AppLockController())
}
