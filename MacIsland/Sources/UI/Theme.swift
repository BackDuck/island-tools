import SwiftUI
import AppKit

/// Цвета активной темы.
struct ThemePalette {
    let glassTint: Color
    let sidebarFill: Color
    let separator: Color
    let primaryText: Color
    let secondaryText: Color
    let tertiaryText: Color
    let accentFill: Color
    let controlFill: Color
    let rowFill: Color
    let rowHoverFill: Color
    let scrubberTrack: Color
    let scrubberFill: Color
    let borderStroke: Color
    let selectionHighlight: Color
    let accentTint: Color
    let material: NSVisualEffectView.Material
    let isLight: Bool
}

extension AppTheme {
    var palette: ThemePalette {
        switch self {
        case .gray:
            return ThemePalette(
                glassTint: Color.black.opacity(0.55),
                sidebarFill: Color.black.opacity(0.35),
                separator: Color.white.opacity(0.08),
                primaryText: Color.white.opacity(0.92),
                secondaryText: Color.white.opacity(0.55),
                tertiaryText: Color.white.opacity(0.38),
                accentFill: Color.white.opacity(0.14),
                controlFill: Color.white.opacity(0.12),
                rowFill: Color.white.opacity(0.06),
                rowHoverFill: Color.white.opacity(0.1),
                scrubberTrack: Color.white.opacity(0.16),
                scrubberFill: Color.white.opacity(0.9),
                borderStroke: Color.white.opacity(0.12),
                selectionHighlight: Color.white.opacity(0.14),
                accentTint: Color.white.opacity(0.9),
                material: .hudWindow,
                isLight: false
            )
        case .black:
            return ThemePalette(
                glassTint: Color.black.opacity(0.78),
                sidebarFill: Color.black.opacity(0.55),
                separator: Color.white.opacity(0.1),
                primaryText: Color.white.opacity(0.95),
                secondaryText: Color.white.opacity(0.58),
                tertiaryText: Color.white.opacity(0.4),
                accentFill: Color.white.opacity(0.16),
                controlFill: Color.white.opacity(0.14),
                rowFill: Color.white.opacity(0.07),
                rowHoverFill: Color.white.opacity(0.12),
                scrubberTrack: Color.white.opacity(0.18),
                scrubberFill: Color.white,
                borderStroke: Color.white.opacity(0.14),
                selectionHighlight: Color.white.opacity(0.16),
                accentTint: Color.white,
                material: .hudWindow,
                isLight: false
            )
        case .white:
            return ThemePalette(
                glassTint: Color.white.opacity(0.72),
                sidebarFill: Color.black.opacity(0.06),
                separator: Color.black.opacity(0.1),
                primaryText: Color.black.opacity(0.88),
                secondaryText: Color.black.opacity(0.55),
                tertiaryText: Color.black.opacity(0.38),
                accentFill: Color.black.opacity(0.1),
                controlFill: Color.black.opacity(0.08),
                rowFill: Color.black.opacity(0.05),
                rowHoverFill: Color.black.opacity(0.09),
                scrubberTrack: Color.black.opacity(0.14),
                scrubberFill: Color.black.opacity(0.75),
                borderStroke: Color.black.opacity(0.12),
                selectionHighlight: Color.black.opacity(0.1),
                accentTint: Color.black.opacity(0.8),
                material: .sheet,
                isLight: true
            )
        case .red:
            return ThemePalette(
                glassTint: Color(red: 0.22, green: 0.05, blue: 0.06).opacity(0.72),
                sidebarFill: Color(red: 0.18, green: 0.03, blue: 0.04).opacity(0.55),
                separator: Color.white.opacity(0.1),
                primaryText: Color.white.opacity(0.94),
                secondaryText: Color.white.opacity(0.58),
                tertiaryText: Color.white.opacity(0.4),
                accentFill: Color(red: 0.85, green: 0.22, blue: 0.28).opacity(0.35),
                controlFill: Color(red: 0.85, green: 0.22, blue: 0.28).opacity(0.28),
                rowFill: Color.white.opacity(0.06),
                rowHoverFill: Color(red: 0.85, green: 0.22, blue: 0.28).opacity(0.22),
                scrubberTrack: Color.white.opacity(0.16),
                scrubberFill: Color(red: 0.95, green: 0.35, blue: 0.4),
                borderStroke: Color(red: 0.9, green: 0.3, blue: 0.35).opacity(0.35),
                selectionHighlight: Color(red: 0.85, green: 0.22, blue: 0.28).opacity(0.3),
                accentTint: Color(red: 0.95, green: 0.4, blue: 0.42),
                material: .hudWindow,
                isLight: false
            )
        case .green:
            return ThemePalette(
                glassTint: Color(red: 0.04, green: 0.16, blue: 0.1).opacity(0.72),
                sidebarFill: Color(red: 0.03, green: 0.12, blue: 0.08).opacity(0.55),
                separator: Color.white.opacity(0.1),
                primaryText: Color.white.opacity(0.94),
                secondaryText: Color.white.opacity(0.58),
                tertiaryText: Color.white.opacity(0.4),
                accentFill: Color(red: 0.25, green: 0.72, blue: 0.45).opacity(0.32),
                controlFill: Color(red: 0.25, green: 0.72, blue: 0.45).opacity(0.26),
                rowFill: Color.white.opacity(0.06),
                rowHoverFill: Color(red: 0.25, green: 0.72, blue: 0.45).opacity(0.2),
                scrubberTrack: Color.white.opacity(0.16),
                scrubberFill: Color(red: 0.4, green: 0.85, blue: 0.55),
                borderStroke: Color(red: 0.35, green: 0.8, blue: 0.5).opacity(0.35),
                selectionHighlight: Color(red: 0.25, green: 0.72, blue: 0.45).opacity(0.28),
                accentTint: Color(red: 0.45, green: 0.9, blue: 0.6),
                material: .hudWindow,
                isLight: false
            )
        case .orange:
            return ThemePalette(
                glassTint: Color(red: 0.18, green: 0.09, blue: 0.03).opacity(0.74),
                sidebarFill: Color(red: 0.14, green: 0.07, blue: 0.02).opacity(0.55),
                separator: Color.white.opacity(0.1),
                primaryText: Color.white.opacity(0.94),
                secondaryText: Color.white.opacity(0.58),
                tertiaryText: Color.white.opacity(0.4),
                accentFill: Color(red: 0.95, green: 0.5, blue: 0.15).opacity(0.32),
                controlFill: Color(red: 0.95, green: 0.5, blue: 0.15).opacity(0.26),
                rowFill: Color.white.opacity(0.06),
                rowHoverFill: Color(red: 0.95, green: 0.5, blue: 0.15).opacity(0.22),
                scrubberTrack: Color.white.opacity(0.16),
                scrubberFill: Color(red: 0.98, green: 0.58, blue: 0.22),
                borderStroke: Color(red: 0.95, green: 0.55, blue: 0.2).opacity(0.4),
                selectionHighlight: Color(red: 0.95, green: 0.5, blue: 0.15).opacity(0.3),
                accentTint: Color(red: 1.0, green: 0.62, blue: 0.28),
                material: .hudWindow,
                isLight: false
            )
        case .blue:
            return ThemePalette(
                glassTint: Color(red: 0.04, green: 0.1, blue: 0.22).opacity(0.74),
                sidebarFill: Color(red: 0.03, green: 0.07, blue: 0.16).opacity(0.55),
                separator: Color.white.opacity(0.1),
                primaryText: Color.white.opacity(0.94),
                secondaryText: Color.white.opacity(0.58),
                tertiaryText: Color.white.opacity(0.4),
                accentFill: Color(red: 0.25, green: 0.5, blue: 0.95).opacity(0.32),
                controlFill: Color(red: 0.25, green: 0.5, blue: 0.95).opacity(0.26),
                rowFill: Color.white.opacity(0.06),
                rowHoverFill: Color(red: 0.25, green: 0.5, blue: 0.95).opacity(0.22),
                scrubberTrack: Color.white.opacity(0.16),
                scrubberFill: Color(red: 0.4, green: 0.65, blue: 1.0),
                borderStroke: Color(red: 0.35, green: 0.6, blue: 0.95).opacity(0.4),
                selectionHighlight: Color(red: 0.25, green: 0.5, blue: 0.95).opacity(0.3),
                accentTint: Color(red: 0.45, green: 0.7, blue: 1.0),
                material: .hudWindow,
                isLight: false
            )
        }
    }

    /// Кружок цвета в сетке тем.
    var swatchColor: Color {
        switch self {
        case .gray: return Color(white: 0.45)
        case .black: return Color.black
        case .white: return Color.white
        case .red: return Color(red: 0.9, green: 0.28, blue: 0.32)
        case .green: return Color(red: 0.3, green: 0.78, blue: 0.45)
        case .orange: return Color(red: 0.95, green: 0.55, blue: 0.2)
        case .blue: return Color(red: 0.25, green: 0.55, blue: 0.95)
        }
    }
}

/// Размеры и задержки панели; цвета — через AppTheme.palette / environment.
enum IslandTheme {
    static let panelWidth: CGFloat = 520
    /// Чуть выше, чтобы под notch остался воздух и контролы не прилипали к низу.
    static let panelHeight: CGFloat = 280
    /// Нижнее скругление (остров вниз).
    static let cornerRadius: CGFloat = 28
    /// Верх почти без radius — вплотную к краю экрана/notch.
    static let topCornerRadius: CGFloat = 2
    static let sidebarWidth: CGFloat = 56

    static let collapsedWidth: CGFloat = 180
    static let collapsedHeight: CGFloat = 28

    /// Задержка перед скрытием, чтобы успеть доехать курсором до панели.
    static let hideDelay: TimeInterval = 0.35
    /// Короткий hover в hotspot, чтобы быстрый проезд по верхнему краю не мигал.
    static let showDelay: TimeInterval = 0.1

    /// Воздух ниже нижней границы notch/island (pt).
    static let contentTopBreathing: CGFloat = 14

    /// Горизонтальный отступ контента после sidebar / до правого края.
    static let contentHorizontalPadding: CGFloat = 18
    /// Нижний отступ контента / контролов (воздух над скруглением).
    static let contentBottomPadding: CGFloat = 20
    /// Ритм между блоками (обложка → прогресс → кнопки).
    static let contentBlockGap: CGFloat = 12
    /// Зазор между иконками в sidebar.
    static let sidebarItemGap: CGFloat = 8

    /// Верхний отступ контента: clearance notch/menu bar + дыхание 14pt.
    /// Окно по-прежнему geometrically под notch — сдвигается только контент.
    static var contentTopInset: CGFloat {
        guard let screen = NSScreen.main else { return 30 + contentTopBreathing }
        let menuBar = max(0, screen.frame.maxY - screen.visibleFrame.maxY)
        let notch = screen.safeAreaInsets.top
        let status = NSStatusBar.system.thickness
        let clearance = max(menuBar, max(notch, max(status, 30)))
        return clearance + contentTopBreathing
    }

    // Совместимость: дефолтная (серая) палитра, если environment ещё нет.
    static var glassTint: Color { AppTheme.gray.palette.glassTint }
    static var sidebarFill: Color { AppTheme.gray.palette.sidebarFill }
    static var separator: Color { AppTheme.gray.palette.separator }
    static var primaryText: Color { AppTheme.gray.palette.primaryText }
    static var secondaryText: Color { AppTheme.gray.palette.secondaryText }
    static var tertiaryText: Color { AppTheme.gray.palette.tertiaryText }
    static var accentFill: Color { AppTheme.gray.palette.accentFill }
    static var controlFill: Color { AppTheme.gray.palette.controlFill }

    static let headerFont = Font.system(size: 11, weight: .semibold, design: .default)
    static let titleFont = Font.system(size: 16, weight: .semibold, design: .default)
    static let subtitleFont = Font.system(size: 13, weight: .regular, design: .default)
}

// MARK: - Environment

private struct ThemePaletteKey: EnvironmentKey {
    static let defaultValue = AppTheme.gray.palette
}

extension EnvironmentValues {
    var themePalette: ThemePalette {
        get { self[ThemePaletteKey.self] }
        set { self[ThemePaletteKey.self] = newValue }
    }
}

extension View {
    func themePalette(_ palette: ThemePalette) -> some View {
        environment(\.themePalette, palette)
    }
}
