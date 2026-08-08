import SwiftUI

struct ClipboardTextTabView: View {
    let items: [ClipboardTextItem]
    var onCopy: (ClipboardTextItem) -> Void
    var onReorder: (ClipboardTextItem) -> Void
    var onDelete: (ClipboardTextItem) -> Void

    @Environment(\.themePalette) private var palette
    @State private var hoveredID: UUID?
    @StateObject private var flash = CopyFlashController()

    /// Фиксированная высота строки — trash не влияет на layout.
    private let rowHeight: CGFloat = 44

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(IslandTab.clipboardText.title)
                .font(IslandTheme.headerFont)
                .tracking(1.2)
                .foregroundStyle(palette.tertiaryText)
                .padding(.leading, IslandTheme.contentHorizontalPadding)

            if items.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(items) { item in
                            textRow(item)
                        }
                    }
                    .padding(.horizontal, IslandTheme.contentHorizontalPadding)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func textRow(_ item: ClipboardTextItem) -> some View {
        let hovered = hoveredID == item.id
        return HStack(alignment: .center, spacing: 8) {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 11))
                .foregroundStyle(palette.tertiaryText)
            Text(item.text)
                .font(.system(size: 12))
                .foregroundStyle(palette.primaryText)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .frame(height: rowHeight)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(hovered ? palette.rowHoverFill : palette.rowFill)
        )
        .overlay(alignment: .trailing) {
            Button {
                onDelete(item)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.secondaryText)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(palette.controlFill))
            }
            .buttonStyle(.plain)
            .help("Удалить")
            .padding(.trailing, 8)
            .opacity(hovered ? 1 : 0)
            .allowsHitTesting(hovered)
        }
        .copyShimmer(flash.isFlashing(item.id), cornerRadius: 10)
        .contentShape(Rectangle())
        .onTapGesture { copy(item) }
        .help("Скопировать в буфер")
        .onHover { inside in
            hoveredID = inside ? item.id : (hoveredID == item.id ? nil : hoveredID)
        }
        .contextMenu {
            Button("Скопировать в буфер") { copy(item) }
            Button("Удалить", role: .destructive) { onDelete(item) }
        }
    }

    private func copy(_ item: ClipboardTextItem) {
        // 1) pasteboard  2) shimmer до конца  3) только потом reorder
        onCopy(item)
        flash.flash(item.id, duration: 0.5) {
            onReorder(item)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(palette.tertiaryText)
            Text("Пока пусто")
                .font(.system(size: 13))
                .foregroundStyle(palette.secondaryText)
            Text("Скопируй текст — он появится здесь")
                .font(.system(size: 11))
                .foregroundStyle(palette.tertiaryText)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
