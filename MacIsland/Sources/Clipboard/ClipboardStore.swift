import Foundation
import AppKit

struct ClipboardTextItem: Identifiable, Codable, Equatable {
    let id: UUID
    let text: String
    let createdAt: Date
}

struct ClipboardImageItem: Identifiable, Codable, Equatable {
    let id: UUID
    let filename: String
    let createdAt: Date

    var fileURL: URL {
        ClipboardStore.shared.imagesDirectory.appendingPathComponent(filename)
    }
}

/// Хранение истории буфера в Application Support.
final class ClipboardStore {
    static let shared = ClipboardStore()

    private var maxText = 50
    private var maxImages = 15
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let queue = DispatchQueue(label: "dev.nursat.MacIsland.clipboardStore")

    private var textItems: [ClipboardTextItem] = []
    private var imageItems: [ClipboardImageItem] = []

    let rootDirectory: URL
    let imagesDirectory: URL
    private let textIndexURL: URL
    private let imageIndexURL: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        rootDirectory = appSupport.appendingPathComponent("MacIsland", isDirectory: true)
        imagesDirectory = rootDirectory.appendingPathComponent("Images", isDirectory: true)
        textIndexURL = rootDirectory.appendingPathComponent("text-history.json")
        imageIndexURL = rootDirectory.appendingPathComponent("image-history.json")

        try? FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        textItems = loadJSON(from: textIndexURL) ?? []
        imageItems = loadJSON(from: imageIndexURL) ?? []
        pruneMissingImages()
    }

    /// Обновить лимиты и обрезать историю, если стало меньше.
    func applyLimits(maxText: Int, maxImages: Int) {
        queue.sync {
            self.maxText = min(max(maxText, 1), 100)
            self.maxImages = min(max(maxImages, 1), 100)
            trimTextIfNeededLocked()
            trimImagesIfNeededLocked()
        }
    }

    func loadTextItems() -> [ClipboardTextItem] {
        queue.sync { textItems }
    }

    func loadImageItems() -> [ClipboardImageItem] {
        queue.sync { imageItems }
    }

    /// Добавить текст, если он новый (не дублирует верхний).
    @discardableResult
    func addText(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        return queue.sync {
            if textItems.first?.text == trimmed { return false }
            let item = ClipboardTextItem(id: UUID(), text: trimmed, createdAt: Date())
            textItems.insert(item, at: 0)
            trimTextIfNeededLocked()
            saveJSON(textItems, to: textIndexURL)
            return true
        }
    }

    /// Добавить картинку с диска.
    @discardableResult
    func addImage(_ image: NSImage) -> Bool {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            return false
        }

        return queue.sync {
            // Не дублируем ту же картинку подряд (по размеру файла)
            if let newest = imageItems.first,
               let attrs = try? FileManager.default.attributesOfItem(atPath: newest.fileURL.path),
               let size = attrs[.size] as? NSNumber,
               size.intValue == png.count {
                return false
            }

            let id = UUID()
            let filename = "\(id.uuidString).png"
            let url = imagesDirectory.appendingPathComponent(filename)
            do {
                try png.write(to: url)
            } catch {
                return false
            }

            let item = ClipboardImageItem(id: id, filename: filename, createdAt: Date())
            imageItems.insert(item, at: 0)
            trimImagesIfNeededLocked()
            saveJSON(imageItems, to: imageIndexURL)
            return true
        }
    }

    /// Только в системный буфер — без reorder списка (для shimmer до подъёма).
    func writeTextToPasteboard(_ item: ClipboardTextItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(item.text, forType: .string)
    }

    /// Поднять запись наверх после анимации копирования.
    func bumpTextToTop(_ item: ClipboardTextItem) {
        queue.sync {
            textItems.removeAll { $0.id == item.id }
            let bumped = ClipboardTextItem(id: item.id, text: item.text, createdAt: Date())
            textItems.insert(bumped, at: 0)
            saveJSON(textItems, to: textIndexURL)
        }
    }

    func writeImageToPasteboard(_ item: ClipboardImageItem) {
        guard let image = NSImage(contentsOf: item.fileURL) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([image])
    }

    func bumpImageToTop(_ item: ClipboardImageItem) {
        queue.sync {
            imageItems.removeAll { $0.id == item.id }
            let bumped = ClipboardImageItem(id: item.id, filename: item.filename, createdAt: Date())
            imageItems.insert(bumped, at: 0)
            saveJSON(imageItems, to: imageIndexURL)
        }
    }

    func deleteText(_ item: ClipboardTextItem) {
        queue.sync {
            textItems.removeAll { $0.id == item.id }
            try? FileManager.default.removeItem(at: item.fileURL)
            saveJSON(imageItems, to: imageIndexURL)
        }
    }

    func deleteImage(_ item: ClipboardImageItem) {
        queue.sync {
            imageItems.removeAll { $0.id == item.id }
            try? FileManager.default.removeItem(at: item.fileURL)
            saveJSON(imageItems, to: imageIndexURL)
        }
    }

    private fun trimTextIfNeededLocked() {
        if textItems.count > maxText {
            textItems = Array(textItems.prefix(maxText))
            saveJSON(textItems, to: textIndexURL)
        }
    }

    private func trimImagesIfNeededLocked() {
        if imageItems.count > maxImages {
            let removed = imageItems.suffix(from: maxImages)
            for old in removed {
                try? FileManager.default.removeItem(at: old.fileURL)
            }
            imageItems = Array(imageItems.prefix(maxImages))
            saveJSON(imageItems, to: imageIndexURL)
        }
    }

    private func pruneMissingImages() {
        // Нельзя трогать ClipboardStore.shared здесь — мы ещё в init.
        imageItems = imageItems.filter { item in
            let url = imagesDirectory.appendingPathComponent(item.filename)
            return FileManager.default.fileExists(atPath: url.path)
        }
        saveJSON(imageItems, to: imageIndexURL)
    }

    private func loadJSON<T: Decodable>(from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }

    private func saveJSON<T: Encodable>(_ value: T, to url: URL) {
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
