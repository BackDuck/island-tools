import Foundation

struct NoteItem: Identifiable, Codable, Equatable {
    let id: UUID
    var text: String
    let createdAt: Date
    var updatedAt: Date
}

/// Короткие заметки рядом с историей буфера в Application Support.
final class NotesStore {
    static let shared = NotesStore()

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let queue = DispatchQueue(label: "dev.nursat.MacIsland.notesStore")
    private var notes: [NoteItem] = []
    private let fileURL: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let root = appSupport.appendingPathComponent("MacIsland", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        fileURL = root.appendingPathComponent("notes.json")

        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601

        notes = loadJSON() ?? []
    }

    func loadNotes() -> [NoteItem] {
        queue.sync { notes }
    }

    @discardableResult
    func add(_ text: String) -> NoteItem? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        return queue.sync {
            let now = Date()
            let item = NoteItem(id: UUID(), text: trimmed, createdAt: now, updatedAt: now)
            notes.insert(item, at: 0)
            save()
            return item
        }
    }

    func update(_ item: NoteItem, text: String) {
        // Пустой текст при правке не удаляет — удаление только явной кнопкой.
        queue.sync {
            guard let idx = notes.firstIndex(where: { $0.id == item.id }) else { return }
            notes[idx].text = text
            notes[idx].updatedAt = Date()
            save()
        }
    }

    func delete(_ item: NoteItem) {
        queue.sync {
            notes.removeAll { $0.id == item.id }
            save()
        }
    }

    private func loadJSON() -> [NoteItem]? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? decoder.decode([NoteItem].self, from: data)
    }

    private func save() {
        guard let data = try? encoder.encode(notes) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
