import Foundation
import Combine

/// Тема оформления панели.
enum AppTheme: String, CaseIterable, Identifiable {
    case gray
    case black
    case white
    case red
    case green
    case orange
    case blue

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gray: return "Серый"
        case .black: return "Чёрный"
        case .white: return "Белый"
        case .red: return "Красный"
        case .green: return "Зелёный"
        case .orange: return "Оранжевый"
        case .blue: return "Синий"
        }
    }
}

/// Стартовый экран при открытии панели.
enum StartupScreen: String, CaseIterable, Identifiable {
    case music
    case clipboardText
    case clipboardImages
    case notes
    case lastOpened

    var id: String { rawValue }

    var title: String {
        switch self {
        case .music: return "Музыка"
        case .clipboardText: return "Буфер обмена: строки"
        case .clipboardImages: return "Буфер обмена: изображения"
        case .notes: return "Заметки"
        case .lastOpened: return "Последняя открытая"
        }
    }

    var tab: IslandTab? {
        switch self {
        case .music: return .music
        case .clipboardText: return .clipboardText
        case .clipboardImages: return .clipboardImages
        case .notes: return .notes
        case .lastOpened: return nil
        }
    }
}

/// Настройки пользователя (UserDefaults).
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private enum Keys {
        static let theme = "appTheme"
        static let maxText = "maxTextItems"
        static let maxImages = "maxImageItems"
        static let startup = "startupScreen"
        static let lastTab = "lastOpenedTab"
        static let clipboardWave = "clipboardWaveEnabled"
    }

    @Published var theme: AppTheme {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: Keys.theme)
        }
    }

    @Published var maxTextItems: Int {
        didSet {
            let clamped = min(max(maxTextItems, 1), 100)
            if clamped != maxTextItems {
                maxTextItems = clamped
                return
            }
            UserDefaults.standard.set(clamped, forKey: Keys.maxText)
            ClipboardStore.shared.applyLimits(maxText: clamped, maxImages: maxImageItems)
        }
    }

    @Published var maxImageItems: Int {
        didSet {
            let clamped = min(max(maxImageItems, 1), 100)
            if clamped != maxImageItems {
                maxImageItems = clamped
                return
            }
            UserDefaults.standard.set(clamped, forKey: Keys.maxImages)
            ClipboardStore.shared.applyLimits(maxText: maxTextItems, maxImages: clamped)
        }
    }

    @Published var startupScreen: StartupScreen {
        didSet {
            UserDefaults.standard.set(startupScreen.rawValue, forKey: Keys.startup)
        }
    }

    /// Волна вокруг island при новой записи в буфер.
    @Published var clipboardWaveEnabled: Bool {
        didSet {
            UserDefaults.standard.set(clipboardWaveEnabled, forKey: Keys.clipboardWave)
        }
    }

    /// Последняя не-settings вкладка (для «Последняя открытая»).
    private(set) var lastOpenedTab: IslandTab

    /// Версия для UI — согласована с Info.plist.
    var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: Keys.theme) ?? AppTheme.gray.rawValue
        theme = AppTheme(rawValue: raw) ?? .gray

        let text = UserDefaults.standard.object(forKey: Keys.maxText) as? Int ?? 50
        maxTextItems = min(max(text, 1), 100)

        let images = UserDefaults.standard.object(forKey: Keys.maxImages) as? Int ?? 15
        maxImageItems = min(max(images, 1), 100)

        let startRaw = UserDefaults.standard.string(forKey: Keys.startup) ?? StartupScreen.music.rawValue
        startupScreen = StartupScreen(rawValue: startRaw) ?? .music

        clipboardWaveEnabled =
            UserDefaults.standard.object(forKey: Keys.clipboardWave) as? Bool ?? true

        let lastRaw = UserDefaults.standard.integer(forKey: Keys.lastTab)
        lastOpenedTab = IslandTab(rawValue: lastRaw) ?? .music

        ClipboardStore.shared.applyLimits(maxText: maxTextItems, maxImages: maxImageItems)
    }

    func rememberLastTab(_ tab: IslandTab) {
        lastOpenedTab = tab
        UserDefaults.standard.set(tab.rawValue, forKey: Keys.lastTab)
    }

    /// Вкладка, которую открыть при показе панели.
    func tabForPanelOpen() -> IslandTab {
        switch startupScreen {
        case .lastOpened:
            return lastOpenedTab
        case .music, .clipboardText, .clipboardImages, .notes:
            return startupScreen.tab ?? .music
        }
    }
}
