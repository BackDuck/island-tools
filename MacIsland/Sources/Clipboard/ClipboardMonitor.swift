import AppKit

/// Следит за NSPasteboard.changeCount и сохраняет текст/картинки.
final class ClipboardMonitor {
    /// kind: "text" | "image"
    var onChange: ((String) -> Void)?

    private let store: ClipboardStore
    private var timer: Timer?
    private var lastChangeCount: Int = -1
    /// Игнор следующей своей записи в буфер (клик по истории).
    private var ignoreUpToChangeCount: Int?

    init(store: ClipboardStore) {
        self.store = store
    }

    func start() {
        lastChangeCount = NSPasteboard.general.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.poll()
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Вызвать сразу после своей записи в NSPasteboard — не добавляем дубль в историю.
    func acknowledgeOwnWrite() {
        let count = NSPasteboard.general.changeCount
        lastChangeCount = count
        ignoreUpToChangeCount = count
        NSLog("[MacIsland][Pulse] acknowledgeOwnWrite changeCount=%d (no flash)", count)
    }

    private func poll() {
        let pb = NSPasteboard.general
        let count = pb.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count

        if let ignore = ignoreUpToChangeCount, count <= ignore {
            NSLog("[MacIsland][Pulse] skip own write changeCount=%d", count)
            ignoreUpToChangeCount = nil
            return
        }
        ignoreUpToChangeCount = nil

        var kind: String?

        // Картинка приоритетнее: иначе вместе с PNG часто копируется мусорный текст
        if let image = readImage(from: pb) {
            if store.addImage(image) {
                kind = "image"
            }
        } else if let str = pb.string(forType: .string), !str.isEmpty {
            if str.count <= 200_000, store.addText(str) {
                kind = "text"
            }
        }

        if let kind {
            NSLog("[MacIsland][Pulse] store added kind=%@ changeCount=%d", kind as NSString, count)
            onChange?(kind)
        } else {
            NSLog("[MacIsland][Pulse] pasteboard changed but store unchanged changeCount=%d", count)
        }
    }

    private func readImage(from pb: NSPasteboard) -> NSImage? {
        if let objs = pb.readObjects(forClasses: [NSImage.self], options: nil),
           let image = objs.first as? NSImage {
            return image
        }
        if let data = pb.data(forType: .tiff) ?? pb.data(forType: .png) {
            return NSImage(data: data)
        }
        return nil
    }
}
