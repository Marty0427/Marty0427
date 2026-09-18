import SwiftUI

/// One pass in the wallet grid: the colour, the name, and enough of the code to recognise it.
struct CardTileView: View {
    let card: WalletCard

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: card.category.symbolName)
                        .font(.caption)
                    Text(card.category.displayName.uppercased())
                        .font(.caption2.weight(.semibold))
                        .tracking(0.6)
                }
                .foregroundStyle(card.theme.foregroundColor.opacity(0.85))

                Text(card.displayName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(card.theme.foregroundColor)
                    .lineLimit(2)

                if !card.organization.isEmpty {
                    Text(card.organization)
                        .font(.subheadline)
                        .foregroundStyle(card.theme.foregroundColor.opacity(0.85))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                expiryBadge
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 8) {
                if card.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(card.theme.foregroundColor)
                }
                BarcodeView(
                    payload: card.payload,
                    symbology: card.symbology,
                    showsHumanReadable: false,
                    padding: 6
                )
                .frame(width: 92)
            }
        }
        .padding(16)
        .frame(minHeight: 132)
        .background(card.theme.gradient)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var expiryBadge: some View {
        if card.isExpired() {
            badge(text: "Expired", systemImage: "exclamationmark.circle.fill")
        } else if card.isExpiringSoon(), let date = card.expirationDate {
            badge(
                text: "Expires \(date.formatted(date: .abbreviated, time: .omitted))",
                systemImage: "clock.fill"
            )
        }
    }

    private func badge(text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.black.opacity(0.25), in: Capsule())
            .foregroundStyle(card.theme.foregroundColor)
    }

    private var accessibilityLabel: String {
        var parts = [card.displayName]
        if !card.organization.isEmpty { parts.append(card.organization) }
        parts.append(card.category.displayName)
        if card.isFavorite { parts.append("Favourite") }
        if card.isExpired() { parts.append("Expired") }
        return parts.joined(separator: ", ")
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 16) {
            ForEach(WalletCard.samples) { card in
                CardTileView(card: card)
            }
        }
        .padding()
    }
    .background(Color(.systemGroupedBackground))
}
