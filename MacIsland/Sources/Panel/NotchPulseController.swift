import AppKit
import QuartzCore

/// Волна вокруг island: скруглённые прямоугольники растут от чёрного pill наружу (scale),
/// низ и бока выглядывают по периметру — не отдельным блоком ниже notch.
final class NotchPulseController {
    private var panel: WavePanel?
    private var host: WaveHostView?
    private var generation = 0

    func flash(accent: NSColor = .white, kind: String = "unknown") {
        assert(Thread.isMainThread, "NotchPulseController.flash must be on main")
        generation += 1
        let gen = generation

        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            NSLog("[MacIsland][Pulse] wave abort: no screen kind=%@", kind as NSString)
            return
        }

        let island = islandMetrics(on: screen)
        let frame = waveWindowFrame(island: island, on: screen)
        let panel = ensurePanel(size: frame.size)
        panel.setFrame(frame, display: true)
        host?.frame = panel.contentView?.bounds ?? .zero

        panel.alphaValue = 1
        panel.orderFrontRegardless()
        panel.setFrame(frame, display: true)

        NSLog(
            "[MacIsland][Pulse] wave show kind=%@ gen=%d island=%.0fx%.0f center=(%.0f,%.0f) frame=(%.0f,%.0f %.0fx%.0f) notch=%.0f",
            kind as NSString,
            gen,
            island.width, island.height,
            island.centerX, island.centerY,
            frame.origin.x, frame.origin.y, frame.width, frame.height,
            screen.safeAreaInsets.top
        )

        host?.playWave(
            accent: accent,
            islandWidth: island.width,
            islandHeight: island.height,
            generation: gen
        ) { [weak self, weak panel] finishedGen in
            guard let self, let panel else { return }
            guard self.generation == finishedGen else { return }
            panel.orderOut(nil)
            NSLog("[MacIsland][Pulse] wave end gen=%d", finishedGen)
        }
    }

    private struct IslandMetrics {
        var centerX: CGFloat
        var centerY: CGFloat
        var width: CGFloat
        var height: CGFloat
    }

    private func islandMetrics(on screen: NSScreen) -> IslandMetrics {
        let height = max(min(screen.safeAreaInsets.top * 0.7, 36), 30)
        let width: CGFloat = {
            if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
                let gap = right.minX - left.maxX
                return max(gap * 0.9, 140)
            }
            return IslandTheme.collapsedWidth
        }()
        let centerX: CGFloat = {
            if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
                return (left.maxX + right.minX) / 2
            }
            return screen.frame.midX
        }()
        // Эпицентр = геометрический центр чёрного island у верха экрана.
        let centerY = screen.frame.maxY - height / 2
        return IslandMetrics(centerX: centerX, centerY: centerY, width: width, height: height)
    }

    private func ensurePanel(size: CGSize) -> WavePanel {
        if let panel {
            return panel
        }

        let p = WavePanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 3)
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .transient]
        p.ignoresMouseEvents = true
        p.hidesOnDeactivate = false
        p.isFloatingPanel = true
        p.becomesKeyOnlyIfNeeded = false
        p.animationBehavior = .none

        let view = WaveHostView(frame: NSRect(origin: .zero, size: size))
        view.autoresizingMask = [.width, .height]
        p.contentView = view
        host = view
        panel = p
        return p
    }

    /// Окно центрировано на island: кольца растут наружу, выглядывают низ/бока.
    private func waveWindowFrame(island: IslandMetrics, on screen: NSScreen) -> NSRect {
        // Запас под scale ~1.65 + stroke/glow, чтобы периметр не обрезался.
        let endScale: CGFloat = 1.65
        let glowPad: CGFloat = 28
        let width = max(island.width * endScale + glowPad * 2, 320)
        let height = max(island.height * endScale + glowPad * 2, 110)
        let x = island.centerX - width / 2
        let y = island.centerY - height / 2
        return NSRect(x: x, y: y, width: width, height: height)
    }
}

private final class WavePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

/// Рябь формой island: широкий rounded-rect, scale от центра pill, aspect сохраняется.
private final class WaveHostView: NSView {
    private var playGeneration = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func playWave(
        accent: NSColor,
        islandWidth: CGFloat,
        islandHeight: CGFloat,
        generation: Int,
        completion: @escaping (Int) -> Void
    ) {
        playGeneration = generation
        layer?.sublayers?.forEach { $0.removeFromSuperlayer() }

        let bounds = self.bounds
        guard bounds.width > 40, bounds.height > 40 else {
            completion(generation)
            return
        }

        // Старт ≈ размер системного island; scale сохраняет aspect (не equal outset).
        let baseW = min(max(islandWidth, 140), bounds.width * 0.62)
        let baseH = min(max(islandHeight, 30), 36)
        // Pill-like: почти половина высоты, но не круг.
        let cornerRatio: CGFloat = 0.48

        // Эпицентр = центр окна = центр чёрного island.
        let center = CGPoint(x: bounds.midX, y: bounds.midY)

        let bright = (accent.blended(withFraction: 0.4, of: .white) ?? .white)
        let ringCount = 2
        let duration: CFTimeInterval = 0.7
        let stagger: CFTimeInterval = 0.11
        // Умеренно наружу: низ и бока выглядывают из-под pill.
        let endScale: CGFloat = 1.55

        for i in 0..<ringCount {
            let lineW: CGFloat = i == 0 ? 3.2 : 2.4
            let ring = CAShapeLayer()
            ring.fillColor = NSColor.clear.cgColor
            ring.strokeColor = bright.withAlphaComponent(0.98).cgColor
            ring.lineWidth = lineW
            ring.lineJoin = .round
            ring.lineCap = .round
            ring.shadowColor = bright.cgColor
            ring.shadowOpacity = 0.95
            ring.shadowRadius = 10
            ring.shadowOffset = .zero
            ring.opacity = 1

            ring.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            ring.bounds = CGRect(x: 0, y: 0, width: baseW, height: baseH)
            ring.position = center
            ring.path = islandPathInLocalBounds(
                width: baseW,
                height: baseH,
                cornerRatio: cornerRatio,
                lineWidth: lineW
            )
            layer?.addSublayer(ring)

            let delay = CFTimeInterval(i) * stagger
            let begin = CACurrentMediaTime() + delay

            let scaleAnim = CABasicAnimation(keyPath: "transform.scale")
            scaleAnim.fromValue = 1.0
            scaleAnim.toValue = endScale
            scaleAnim.duration = duration
            scaleAnim.beginTime = begin
            scaleAnim.timingFunction = CAMediaTimingFunction(name: .easeOut)
            scaleAnim.fillMode = .forwards
            scaleAnim.isRemovedOnCompletion = false

            let fadeAnim = CABasicAnimation(keyPath: "opacity")
            fadeAnim.fromValue = 1.0
            fadeAnim.toValue = 0
            fadeAnim.duration = duration
            fadeAnim.beginTime = begin
            fadeAnim.timingFunction = CAMediaTimingFunction(name: .easeOut)
            fadeAnim.fillMode = .forwards
            fadeAnim.isRemovedOnCompletion = false

            ring.add(scaleAnim, forKey: "wave.scale")
            ring.add(fadeAnim, forKey: "wave.fade")
        }

        let total = duration + stagger * CFTimeInterval(ringCount - 1) + 0.05
        NSLog(
            "[MacIsland][Pulse] wave anim gen=%d rects=%d base=%.0fx%.0f scale=%.2f center=(%.0f,%.0f)",
            generation, ringCount, baseW, baseH, endScale, center.x, center.y
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + total) { [weak self] in
            guard let self, self.playGeneration == generation else { return }
            self.layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
            completion(generation)
        }
    }

    private func islandPathInLocalBounds(
        width: CGFloat,
        height: CGFloat,
        cornerRatio: CGFloat,
        lineWidth: CGFloat
    ) -> CGPath {
        let inset = lineWidth / 2
        let rect = CGRect(
            x: inset,
            y: inset,
            width: max(width - lineWidth, 1),
            height: max(height - lineWidth, 1)
        )
        let corner = min(rect.height * cornerRatio, rect.width * 0.2)
        return CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)
    }
}
