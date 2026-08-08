import SwiftUI
import AppKit

/// Корневой UI: glass pill + sidebar + контент вкладки.
struct IslandContentView: View {
    @ObservedObject var state: IslandState
    @ObservedObject var settings: AppSettings
    var onPlayPause: () -> Void
    var onNext: () -> Void
    var onPrev: () -> Void
    var onSeek: (Double) -> Void
    var onCopyText: (ClipboardTextItem) -> Void
    var onReorderText: (ClipboardTextItem) -> Void
    var onCopyImage: (ClipboardImageItem) -> Void
    var onReorderImage: (ClipboardImageItem) -> Void
    var onDeleteText: (ClipboardTextItem) -> Void
    var onDeleteImage: (ClipboardImageItem) -> Void
    var onAddNote: (String) -> Void
    var onUpdateNote: (NoteItem, String) -> Void
    var onDeleteNote: (NoteItem) -> Void

    @State private var borderPulse = false
    @State private var pulseGeneration = 0

    private var palette: ThemePalette { settings.theme.palette }

    var body: some View {
        ZStack {
            VisualEffectView(material: palette.material, blendingMode: .behindWindow)

            IslandShape.panel
                .fill(palette.glassTint)

            HStack(spacing: 0) {
                SidebarView(
                    selected: $state.selectedTab,
                    showingSettings: $state.showingSettings,
                    onSelectTab: { state.selectTab($0) }
                )
                .frame(width: IslandTheme.sidebarWidth)

                Rectangle()
                    .fill(palette.separator)
                    .frame(width: 1)
                    .padding(.top, IslandTheme.contentTopInset)
                    .padding(.bottom, IslandTheme.contentBottomPadding)

                Group {
                    if state.showingSettings {
                        SettingsTabView(settings: settings)
                    } else {
                        switch state.selectedTab {
                        case .music:
                            MusicTabView(
                                info: state.nowPlaying,
                                onPlayPause: onPlayPause,
                                onNext: onNext,
                                onPrev: onPrev,
                                onSeek: onSeek
                            )
                        case .clipboardText:
                            ClipboardTextTabView(
                                items: state.textItems,
                                onCopy: onCopyText,
                                onReorder: onReorderText,
                                onDelete: onDeleteText
                            )
                        case .clipboardImages:
                            ClipboardImagesTabView(
                                items: state.imageItems,
                                onCopy: onCopyImage,
                                onReorder: onReorderImage,
                                onDelete: onDeleteImage
                            )
                        case .notes:
                            NotesTabView(
                                notes: state.notes,
                                onAdd: onAddNote,
                                onUpdate: onUpdateNote,
                                onDelete: onDeleteNote
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, IslandTheme.contentTopInset)
                .padding(.trailing, IslandTheme.contentHorizontalPadding)
                .padding(.bottom, IslandTheme.contentBottomPadding)
            }
        }
        // Жёсткая маска острова — скругление снизу не съедается overflow.
        .clipShape(IslandShape.panel)
        .compositingGroup()
        .overlay {
            IslandShape.panel
                .strokeBorder(
                    borderPulse ? Color.white.opacity(0.95) : palette.borderStroke,
                    lineWidth: borderPulse ? 3 : 0.5
                )
                .shadow(
                    color: borderPulse ? palette.accentTint.opacity(0.85) : .clear,
                    radius: borderPulse ? 16 : 0
                )
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .themePalette(palette)
        .onChange(of: state.clipboardPulseToken) { _, token in
            guard token != nil else { return }
            runBorderPulse()
        }
        .onChange(of: settings.maxTextItems) { _, _ in
            state.reloadClipboard()
        }
        .onChange(of: settings.maxImageItems) { _, _ in
            state.reloadClipboard()
        }
    }

    /// Два ярких импульса по контуру (~0.85с).
    private func runBorderPulse() {
        pulseGeneration += 1
        let gen = pulseGeneration
        borderPulse = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            guard pulseGeneration == gen else { return }
            borderPulse = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                guard pulseGeneration == gen else { return }
                borderPulse = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                    guard pulseGeneration == gen else { return }
                    borderPulse = false
                }
            }
        }
    }
}
