import AppKit
import Combine
import QuartzCore
import SwiftUI

/// Управляет показом/скрытием панели и позиционированием под notch.
final class IslandPanelController: NSObject {
    var onHoverChange: ((Bool) -> Void)?

    private let state: IslandState
    private let settings: AppSettings
    private let media: MediaRemoteController
    private let onCopyText: (ClipboardTextItem) -> Void
    private let onReorderText: (ClipboardTextItem) -> Void
    private let onCopyImage: (ClipboardImageItem) -> Void
    private let onReorderImage: (ClipboardImageItem) -> Void
    private let onDeleteText: (ClipboardTextItem) -> Void
    private let onDeleteImage: (ClipboardImageItem) -> Void
    private let onAddNote: (String) -> Void
    private let onUpdateNote: (NoteItem, String) -> Void
    private let onDeleteNote: (NoteItem) -> Void
    private var panel: IslandPanel!
    private var hosting: NSHostingView<AnyView>!
    private var isExpanded = false
    /// Когда панель в последний раз схлопнулась; нужно, чтобы быстрый повторный показ не сбрасывал вкладку.
    private var lastCollapsedAt: CFAbsoluteTime?
    private static let reopenKeepStateThreshold: CFTimeInterval = 1.0
    private var tabObserver: AnyCancellable?
    private let notchPulse = NotchPulseController()

    init(
        state: IslandState,
        settings: AppSettings,
        media: MediaRemoteController,
        onCopyText: @escaping (ClipboardTextItem) -> Void,
        onReorderText: @escaping (ClipboardTextItem) -> Void,
        onCopyImage: @escaping (ClipboardImageItem) -> Void,
        onReorderImage: @escaping (ClipboardImageItem) -> Void,
        onDeleteText: @escaping (ClipboardTextItem) -> Void,
        onDeleteImage: @escaping (ClipboardImageItem) -> Void,
        onAddNote: @escaping (String) -> Void,
        onUpdateNote: @escaping (NoteItem, String) -> Void,
        onDeleteNote: @escaping (NoteItem) -> Void
    ) {
        self.state = state
        self.settings = settings
        self.media = media
        self.onCopyText = onCopyText
        self.onReorderText = onReorderText
        self.onCopyImage = onCopyImage
        self.onReorderImage = onReorderImage
        self.onDeleteText = onDeleteText
        self.onDeleteImage = onDeleteImage
        self.onAddNote = onAddNote
        self.onUpdateNote = onUpdateNote
        self.onDeleteNote = onDeleteNote
        super.init()
        setupPanel()
        tabObserver = state.$selectedTab.sink { [weak self] tab in
            guard tab == .notes, self?.state.showingSettings == false else { return }
            DispatchQueue.main.async {
                self?.panel.makeKeyAndOrderFront(nil)
            }
        }
    }

    /// Экранный frame панели, пока она раскрыта (для hover hit-test).
    var panelScreenFrame: CGRect? {
        guard isExpanded, panel.isVisible else { return nil }
        return panel.frame
    }

    var isPanelExpanded: Bool { isExpanded }

    /// - Parameter openNotes: ⌘/Control-hover — сразу Заметки, без настройки «При открытии».
    func showExpanded(openNotes: Bool = false) {
        guard let screen = NSScreen.main else { return }
        let frame = expandedFrame(on: screen)
        if !isExpanded {
            // Стартовый экран только при реальном раскрытии, не при каждом hover-refresh.
            // Если снова открыли в течение 1 с после скрытия — оставляем ту же вкладку/settings.
            let reopenQuickly = lastCollapsedAt.map {
                CFAbsoluteTimeGetCurrent() - $0 <= Self.reopenKeepStateThreshold
            } ?? false
            if openNotes {
                state.showingSettings = false
                state.selectedTab = .notes
            } else if !reopenQuickly {
                state.applyStartupScreen(from: settings)
            }
            isExpanded = true
            panel.alphaValue = 0
            panel.setFrame(collapsedFrame(on: screen), display: true)
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.28
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(frame, display: true)
                panel.animator().alphaValue = 1
            }, completionHandler: { [weak self] in
                self?.syncHoverFromMouseLocation()
            })
        } else {
            panel.setFrame(frame, display: true)
            panel.orderFrontRegardless()
            panel.alphaValue = 1
            syncHoverFromMouseLocation()
        }
        if state.selectedTab == .notes, !state.showingSettings {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    func hideExpanded() {
        guard isExpanded, let screen = NSScreen.main else { return }
        isExpanded = false
        lastCollapsedAt = CFAbsoluteTimeGetCurrent()
        let target = collapsedFrame(on: screen)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, !self.isExpanded else { return }
            self.panel.orderOut(nil)
            self.onHoverChange?(false)
        })
    }

    /// Вспышка при новой записи буфера. Всегда зовём на main.
    func flashClipboardArrival(kind: String = "unknown") {
        assert(Thread.isMainThread)
        guard settings.clipboardWaveEnabled else { return }

        let accent: NSColor = {
            switch settings.theme {
            case .red: return NSColor(calibratedRed: 0.95, green: 0.35, blue: 0.4, alpha: 1)
            case .green: return NSColor(calibratedRed: 0.4, green: 0.85, blue: 0.55, alpha: 1)
            case .orange: return NSColor(calibratedRed: 0.98, green: 0.55, blue: 0.2, alpha: 1)
            case .blue: return NSColor(calibratedRed: 0.35, green: 0.6, blue: 1.0, alpha: 1)
            case .white: return NSColor(calibratedWhite: 0.15, alpha: 1)
            default: return .white
            }
        }()

        NSLog("[MacIsland][Pulse] flashClipboardArrival kind=%@ expanded=%d",
              kind as NSString, isExpanded ? 1 : 0)

        // Всегда отдельный glow у notch — видно и при свёрнутой панели.
        notchPulse.flash(accent: accent, kind: kind)

        if isExpanded {
            // Дополнительно — контур основной панели.
            state.triggerClipboardPulse()
        }
    }

    private func syncHoverFromMouseLocation() {
        guard isExpanded, let content = panel.contentView as? HoverAwareView else { return }
        let loc = NSEvent.mouseLocation
        let inside = panel.frame.insetBy(dx: -2, dy: -2).contains(loc)
        content.reportHover(inside)
    }

    // MARK: - Layout

    private func setupPanel() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        panel = IslandPanel(contentRect: collapsedFrame(on: screen))
        panel.alphaValue = 0

        let root = IslandContentView(
            state: state,
            settings: settings,
            onPlayPause: { [weak self] in self?.media.togglePlayPause() },
            onNext: { [weak self] in self?.media.nextTrack() },
            onPrev: { [weak self] in self?.media.previousTrack() },
            onSeek: { [weak self] f in self?.media.seek(to: f) },
            onCopyText: onCopyText,
            onReorderText: onReorderText,
            onCopyImage: onCopyImage,
            onReorderImage: onReorderImage,
            onDeleteText: onDeleteText,
            onDeleteImage: onDeleteImage,
            onAddNote: onAddNote,
            onUpdateNote: onUpdateNote,
            onDeleteNote: onDeleteNote
        )
        .environmentObject(state)

        hosting = NSHostingView(rootView: AnyView(root))
        hosting.frame = NSRect(origin: .zero, size: panel.frame.size)
        hosting.autoresizingMask = [.width, .height]
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor

        let container = HoverAwareView(frame: hosting.frame)
        container.autoresizingMask = [.width, .height]
        container.onHover = { [weak self] inside in
            self?.onHoverChange?(inside)
        }
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        panel.contentView = container
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
    }

    private func expandedFrame(on screen: NSScreen) -> NSRect {
        let w = IslandTheme.panelWidth
        let h = IslandTheme.panelHeight
        let midX = notchCenterX(on: screen)
        let x = midX - w / 2
        let tuck = min(screen.safeAreaInsets.top * 0.15, 4)
        let y = screen.frame.maxY - h + tuck
        return NSRect(x: x, y: y, width: w, height: h)
    }

    private func collapsedFrame(on screen: NSScreen) -> NSRect {
        let w = IslandTheme.collapsedWidth
        let h = IslandTheme.collapsedHeight
        let midX = notchCenterX(on: screen)
        let x = midX - w / 2
        let tuck = min(screen.safeAreaInsets.top * 0.15, 4)
        let y = screen.frame.maxY - h + tuck
        return NSRect(x: x, y: y, width: w, height: h)
    }

    private func notchCenterX(on screen: NSScreen) -> CGFloat {
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            return (left.maxX + right.minX) / 2
        }
        return screen.frame.midX
    }
}

/// View, которая сообщает о входе/выходе курсора по всему bounds панели.
final class HoverAwareView: NSView {
    var onHover: ((Bool) -> Void)?
    private var tracking: NSTrackingArea?
    private var lastInside = false

    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, alphaValue > 0.01, bounds.contains(point) else { return nil }
        return super.hitTest(point) ?? self
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking {
            removeTrackingArea(tracking)
        }

        let mouseInWindow = window?.mouseLocationOutsideOfEventStream ?? .zero
        let mouseInView = convert(mouseInWindow, from: nil)
        let currentlyInside = !bounds.isEmpty && bounds.contains(mouseInView)

        var options: NSTrackingArea.Options = [
            .mouseEnteredAndExited, .activeAlways, .inVisibleRect
        ]
        if currentlyInside {
            options.insert(.assumeInside)
        }

        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
        if currentlyInside {
            reportHover(true)
        }
    }

    override func mouseEntered(with event: NSEvent) {
        reportHover(true)
    }

    override func mouseExited(with event: NSEvent) {
        reportHover(false)
    }

    func reportHover(_ inside: Bool) {
        guard inside != lastInside else { return }
        lastInside = inside
        onHover?(inside)
    }
}
