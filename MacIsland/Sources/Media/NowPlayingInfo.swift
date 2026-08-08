import Foundation
import AppKit

struct NowPlayingInfo: Equatable {
    var title: String
    var artist: String
    var album: String
    /// Сырые bytes обложки — надёжнее для Equatable/SwiftUI, чем NSImage.
    var artworkData: Data?
    var elapsed: TimeInterval
    var duration: TimeInterval
    var isPlaying: Bool
    var appName: String
    var appBundleIdentifier: String
    var isAvailable: Bool

    static let empty = NowPlayingInfo(
        title: "",
        artist: "",
        album: "",
        artworkData: nil,
        elapsed: 0,
        duration: 0,
        isPlaying: false,
        appName: "",
        appBundleIdentifier: "",
        isAvailable: false
    )

    var artwork: NSImage? {
        guard let artworkData, !artworkData.isEmpty else { return nil }
        return NSImage(data: artworkData)
    }

    var subtitle: String {
        let parts = [artist, album].filter { !$0.isEmpty }
        return parts.joined(separator: " — ")
    }

    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(max(elapsed / duration, 0), 1)
    }

    var hasArtwork: Bool {
        guard let artworkData else { return false }
        return !artworkData.isEmpty
    }
}
