import AppKit
import CoreGraphics

/// Детект наведения на зону notch через global + local mouse monitors.
/// Global нужен, когда фокус в другом приложении.
final class HoverTracker {
    /// Bool = openNotes (⌘/Control — сразу Заметки, без «При открытии»).
    var onShouldExpand: ((Bool) -> Void)?
    var onShouldCollapse: (() -> Void)?
    /// Актуальный frame раскрытой панели в экранных координатах (nil = свёрнута / нет панели).
    var panelFrameProvider: (() -> CGRect?)?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var pollTimer: Timer?
    private var hideWorkItem: DispatchWorkItem?
    private var showWorkItem: DispatchWorkItem?
    private var isExpanded = false
    private var pointerInsidePanel = false

    /// Минимальная ширина зоны, если notch не определён.
    private let fallbackWidth: CGFloat = 180
    /// Keep-alive: недавно были в hotspot — считаем «внутри» ещё ~150 мс.
    private let hysteresis: TimeInterval = 0.15
    private var lastInsideHotspotAt: Date?

    func start() {
        let handler: (NSEvent) -> Void = { [weak self] _ in
            self?.evaluateMouseLocation()
        }

        // flagsChanged — чтобы ⌘/Control на island сразу открыл Заметки без движения мыши.
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .flagsChanged]

        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: mask,
            handler: handler
        )
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: mask
        ) { [weak self] event in
            self?.evaluateMouseLocation()
            return event
        }

        // Периодическая проверка — на случай пропуска событий
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            self?.evaluateMouseLocation()
        }
        if let pollTimer {
            RunLoop.main.add(pollTimer, forMode: .common)
        }
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        globalMonitor = nil
        localMonitor = nil
        pollTimer?.invalidate()
        pollTimer = nil
        cancelHide()
        cancelShow()
    }

    func setPointerInsidePanel(_ inside: Bool) {
        pointerInsidePanel = inside
        evaluateMouseLocation()
    }

    // MARK: - Logic

    private func evaluateMouseLocation() {
        let loc = NSEvent.mouseLocation
        let insideHotspotNow = isInsideHotspot(loc)
        if insideHotspotNow {
            lastInsideHotspotAt = Date()
        }

        let insideHotspot = insideHotspotNow || isWithinHysteresis()
        let insidePanelBounds = isInsidePanelFrame(loc)
        let insidePanel = insidePanelBounds || pointerInsidePanel

        // Пока открыта: tracked = panel ∪ hotspot.
        // Пока закрыта: tracked = hotspot внутри выреза (+ hysteresis).
        let insideTracked = isExpanded
            ? (insidePanel || insideHotspot)
            : insideHotspot

        if insidePanel {
            cancelHide()
            // Не трогаем pending-show: если уже едем к expand — ок.
            expandImmediately(openNotes: false)
            return
        }

        if insideTracked {
            cancelHide()
            // ⌘ (Command) или Control + наведение / hysteresis — сразу Заметки, без showDelay.
            if isOpenNotesModifier {
                cancelShow()
                expandImmediately(openNotes: true)
            } else {
                // Движение внутри hotspot вверх-вниз не отменяет show.
                scheduleShowIfNeeded()
            }
            return
        }

        // Вне tracked-зоны.
        cancelShow()
        scheduleHideIfNeeded()
    }

    private func isWithinHysteresis() -> Bool {
        guard let last = lastInsideHotspotAt else { return false }
        return Date().timeIntervalSince(last) <= hysteresis
    }

    /// ⌘ (Command) / Control — быстрый доступ к Заметкам.
    /// deviceIndependentFlagsMask — чтобы poll timer и flagsChanged одинаково видели флаги с любой клавиатуры.
    private var isOpenNotesModifier: Bool {
        let flags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return flags.contains(.command) || flags.contains(.control)
    }

    private func expandImmediately(openNotes: Bool) {
        guard !isExpanded else { return }
        isExpanded = true
        DispatchQueue.main.async {
            self.onShouldExpand?(openNotes)
        }
    }

    private func scheduleShowIfNeeded() {
        guard !isExpanded else { return }
        guard showWorkItem == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.showWorkItem = nil
            let loc = NSEvent.mouseLocation
            // Повторная проверка: всё ещё в зоне выреза / hysteresis / панели.
            if self.isInsideHotspot(loc)
                || self.isWithinHysteresis()
                || self.isInsidePanelFrame(loc)
                || self.pointerInsidePanel {
                self.expandImmediately(openNotes: false)
            }
        }
        showWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + IslandTheme.showDelay, execute: work)
    }

    private func scheduleHideIfNeeded() {
        guard isExpanded else { return }
        guard hideWorkItem == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.hideWorkItem = nil
            let loc = NSEvent.mouseLocation
            let stillInside =
                self.isInsideHotspot(loc)
                || self.isWithinHysteresis()
                || self.isInsidePanelFrame(loc)
                || self.pointerInsidePanel
            if !stillInside {
                self.isExpanded = false
                self.onShouldCollapse?()
            }
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + IslandTheme.hideDelay, execute: work)
    }

    private func cancelHide() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
    }

    private func cancelShow() {
        showWorkItem?.cancel()
        showWorkItem = nil
    }

    private func isInsidePanelFrame(_ point: CGPoint) -> Bool {
        guard let frame = panelFrameProvider?(), !frame.isEmpty else { return false }
        // Небольшой запас, чтобы не мигать на границе.
        return frame.insetBy(dx: -2, dy: -2).contains(point)
    }

    /// Hotspot строго внутри выреза: по ширине — между menu-bar областями,
    /// по высоте — только верхняя половина notch (нужно зайти примерно наполовину).
    private func isInsideHotspot(_ point: CGPoint) -> Bool {
        guard let screen = screenContaining(point) ?? NSScreen.main else { return false }
        return notchHitZone(on: screen).contains(point)
    }

    private func notchHitZone(on screen: NSScreen) -> CGRect {
        let top = screen.frame.maxY
        let notchHeight = max(screen.safeAreaInsets.top, 1)
        // Нижняя граница зоны — середина выреза; ниже него курсор ещё «снаружи».
        let height = notchHeight * 0.5

        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            let minX = left.maxX
            let maxX = right.minX
            let width = max(maxX - minX, 80)
            return CGRect(x: minX, y: top - height, width: width, height: height)
        }

        // Без notch — узкая полоска у самого верха по центру.
        let width = fallbackWidth
        let x = screen.frame.midX - width / 2
        return CGRect(x: x, y: top - height, width: width, height: height)
    }

    private func screenContaining(_ point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) }
    }
}
