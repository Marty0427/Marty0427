import SwiftUI
import UIKit

/// The screen you hold up at the till: the code, as big and as bright as the phone allows.
struct CardDetailView: View {
    let cardID: UUID
    var onEdit: (WalletCard) -> Void

    @EnvironmentObject private var store: CardStore
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @StateObject private var brightness = ScreenBrightnessController()
    @State private var isConfirmingDelete = false
    @State private var didCopy = false

    var body: some View {
        Group {
            if let card = store.card(with: cardID) {
                content(for: card)
            } else {
                ContentUnavailableView(
                    "Card Deleted",
                    systemImage: "trash",
                    description: Text("This card is no longer in your wallet.")
                )
            }
        }
        .onAppear {
            if settings.boostsBrightness {
                brightness.boost(keepAwake: settings.keepsScreenAwake)
            }
            if let card = store.card(with: cardID) {
                store.markUsed(card)
            }
        }
        .onDisappear {
            brightness.restore()
        }
    }

    private func content(for card: WalletCard) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                BarcodeView(payload: card.payload, symbology: card.symbology)
                    .padding(.horizontal, card.symbology.dimension == .matrix ? 40 : 12)
                    .shadow(color: .black.opacity(0.08), radius: 10, y: 4)

                header(for: card)
                actionRow(for: card)
                details(for: card)
            }
            .padding(20)
        }
        .background(backgroundWash(for: card))
        .navigationTitle(card.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        onEdit(card)
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    Button {
                        store.toggleFavorite(card)
                        Haptics.selection(enabled: settings.hapticsEnabled)
                    } label: {
                        Label(
                            card.isFavorite ? "Remove Favourite" : "Add to Favourites",
                            systemImage: card.isFavorite ? "star.slash" : "star"
                        )
                    }
                    ShareLink(item: card.payload) {
                        Label("Share Code", systemImage: "square.and.arrow.up")
                    }
                    Divider()
                    Button(role: .destructive) {
                        isConfirmingDelete = true
                    } label: {
                        Label("Delete Card", systemImage: "trash")
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog(
            "Delete “\(card.displayName)”?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Card", role: .destructive) {
                store.delete(card)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the card from this device. It can’t be undone.")
        }
    }

    private func header(for card: WalletCard) -> some View {
        VStack(spacing: 6) {
            Text(card.displayName)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
            if !card.organization.isEmpty {
                Text(card.organization)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if card.isExpired() {
                Label("Expired", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
    }

    private func actionRow(for card: WalletCard) -> some View {
        HStack(spacing: 12) {
            Button {
                UIPasteboard.general.string = card.payload
                didCopy = true
                Haptics.success(enabled: settings.hapticsEnabled)
            } label: {
                Label(didCopy ? "Copied" : "Copy Code", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                store.toggleFavorite(card)
                Haptics.selection(enabled: settings.hapticsEnabled)
            } label: {
                Label(
                    card.isFavorite ? "Favourite" : "Add Favourite",
                    systemImage: card.isFavorite ? "star.fill" : "star"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    private func details(for card: WalletCard) -> some View {
        VStack(spacing: 0) {
            detailRow(title: "Format", value: card.symbology.displayName)
            Divider()
            detailRow(title: "Category", value: card.category.displayName)
            if let expiration = card.expirationDate {
                Divider()
                detailRow(
                    title: "Expires",
                    value: expiration.formatted(date: .long, time: .omitted)
                )
            }
            if let lastUsed = card.lastUsedAt {
                Divider()
                detailRow(
                    title: "Last shown",
                    value: lastUsed.formatted(date: .abbreviated, time: .shortened)
                )
            }
            if !card.notes.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Notes")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(card.notes)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func detailRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
    }

    /// A faint tint of the card's own colour, so the pass still feels like itself.
    private func backgroundWash(for card: WalletCard) -> some View {
        LinearGradient(
            colors: [card.theme.startColor.opacity(0.18), Color(.systemGroupedBackground)],
            startPoint: .top,
            endPoint: .center
        )
        .ignoresSafeArea()
    }
}

#Preview {
    let store = CardStore(repository: InMemoryCardRepository(cards: WalletCard.samples))
    return NavigationStack {
        CardDetailView(cardID: WalletCard.samples[0].id) { _ in }
            .environmentObject(store)
            .environmentObject(AppSettings())
    }
}
