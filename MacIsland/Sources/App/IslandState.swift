import Foundation
import AppKit
import Combine

enum IslandTab: Int, CaseIterable, Identifiable {
    case music
    case clipboardText
    case clipboardImages
    case notes

    var id: Int { rawValue }

    /// Заголовок вкладки в UI (caps).
    var title: String {
        switch self {
        case .music: return "МУЗЫКА"
        case .clipboardText: return "БУФЕР ОБМЕНА: СТРОКИ"
        case .clipboardImages: return "БУФЕР ОБМЕНА: ИЗОБРАЖЕНИЯ"
        case .notes: return "ЗАМЕТКИ"
        }
    }

    /// Короткое имя для help / компактных мест.
    var shortTitle: String {
        switch self {
        case .music: return "Музыка"
        case .clipboardText: return "Строки"
        case .clipboardImages: return "Изображения"
        case .notes: return "Заметки"
        }
    }

    var systemImage: String {
        switch self {
        case .music: return "music.note"
        case .clipboardText: return "doc.on.clipboard"
        case .clipboardImages: return "photo.on.rectangle"
        case .notes: return "note.text"
        }
    }
}

/// Общее состояние UI панели (обновляем с главного потока).
final class IslandState: ObservableObject {
    @Published var selectedTab: IslandTab = .music
    @Published var showingSettings = false
    @Published var nowPlaying: NowPlayingInfo = .empty
    @Published var textItems: [ClipboardTextItem] = []
    @Published var imageItems: [ClipboardImageItem] = []
    @Published var notes: [NoteItem] = []
    /// Токен вспышки при новой записи буфера (меняется → один импульс).
    @Published var clipboardPulseToken: UUID?

    func reloadClipboard() {
        textItems = ClipboardStore.shared.loadTextItems()
        imageItems = ClipboardStore.shared.loadImageItems()
    }

    func reloadNotes() {
        notes = NotesStore.shared.loadNotes()
    }

    func triggerClipboardPulse() {
        clipboardPulseToken = UUID()
    }

    func openSettings() {
        showingSettings = true
    }

    func selectTab(_ tab: IslandTab) {
        showingSettings = false
        selectedTab = tab
        AppSettings.shared.rememberLastTab(tab)
    }

    /// Применить стартовый экран из настроек (не settings).
    func applyStartupScreen(from settings: AppSettings) {
        showingSettings = false
        selectedTab = settings.tabForPanelOpen()
    }
}
