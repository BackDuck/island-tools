import AppKit

/// Nonactivating floating panel поверх всего.
final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        // Тень окна рисует прямоугольник — отключаем; форму рисует сам контент.
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .utilityWindow
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isFloatingPanel = true
        // Без стандартной рамки / кнопки тулбара
        styleMask.remove(.titled)
        styleMask.insert(.borderless)
    }

    /// Системный constrain отталкивает окно ниже menu bar — из‑за этого зазор под island.
    /// Разрешаем кадр как есть, чтобы верх панели уходил под notch.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
