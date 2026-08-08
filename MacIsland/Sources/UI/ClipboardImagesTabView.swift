import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ClipboardImagesTabView: View {
    let items: [ClipboardImageItem]
    var onCopy: (ClipboardImageItem) -> Void
    var onReorder: (ClipboardImageItem) -> Void
    var onDelete: (ClipboardImageItem) -> Void

    @Environment(\.themePalette) private var palette
    @State private var hoveredID: UUID?
    @StateObject private var flash = CopyFlashController()

    private let columns = [
        GridItem(.adaptive(minimum: 72, maximum: 96), spacing: 8)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(IslandTab.clipboardImages.title)
                .font(IslandTheme.headerFont)
                .tracking(1.2)
                .foregroundStyle(palette.tertiaryText)
                .padding(.leading, IslandTheme.contentHorizontalPadding)

            if items.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(items) { item in
                            imageCell(item)
                        }
                    }
                    .padding(.horizontal, IslandTheme.contentHorizontalPadding)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func imageCell(_ item: ClipboardImageItem) -> some View {
        let hovered = hoveredID == item.id
        return ZStack(alignment: .topTrailing) {
            thumbnail(for: item)
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(palette.borderStroke, lineWidth: 0.5)
                )
                .copyShimmer(flash.isFlashing(item.id), cornerRadius: 12)
                .contentShape(Rectangle())
                .onTapGesture { copy(item) }
                .help("Скопировать в буфер · тяни наружу")
                .onDrag {
                    dragProvider(for: item)
                }

            Button {
                onDelete(item)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color.black.opacity(0.65)))
            }
            .buttonStyle(.plain)
            .offset(x: 4, y: -4)
            .opacity(hovered ? 1 : 0)
            .allowsHitTesting(hovered)
            .help("Удалить")
        }
        .onHover { inside in
            hoveredID = inside ? item.id : (hoveredID == item.id ? nil : hoveredID)
        }
        .contextMenu {
            Button("Скопировать в буфер") { copy(item) }
            Button("Удалить", role: .destructive) { onDelete(item) }
        }
    }

    private func copy(_ item: ClipboardImageItem) {
        onCopy(item)
        flash.flash(item.id, duration: 0.5) {
            onReorder(item)
        }
    }

    private func dragProvider(for item: ClipboardImageItem) -> NSItemProvider {
        let url = item.fileURL
        if FileManager.default.fileExists(atPath: url.path) {
            let provider = NSItemProvider(contentsOf: url) ?? NSItemProvider()
            if let data = try? Data(contentsOf: url) {
                provider.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { completion in
                    completion(data, nil)
                    return nil
                }
            }
            return provider
        }
        if let image = NSImage(contentsOf: url), let tiff = image.tiffRepresentation {
            let provider = NSItemProvider()
            provider.registerDataRepresentation(forTypeIdentifier: UTType.tiff.identifier, visibility: .all) { completion in
                completion(tiff, nil)
                return nil
            }
            return provider
        }
        return NSItemProvider()
    }

    @ViewBuilder
    private func thumbnail(for item: ClipboardImageItem) -> some View {
        if let image = NSImage(contentsOf: item.fileURL) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                palette.rowFill
                Image(systemName: "photo")
                    .foregroundStyle(palette.tertiaryText)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(palette.tertiaryText)
            Text("Картинок нет")
                .font(.system(size: 13))
                .foregroundStyle(palette.secondaryText)
            Text("Скопируй изображение — сохранится превью")
                .font(.system(size: 11))
                .foregroundStyle(palette.tertiaryText)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
