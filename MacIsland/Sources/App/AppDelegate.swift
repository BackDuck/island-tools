import AppKit
import SwiftUI

/// Точка входа AppKit: панель, hover, буфер, музыка.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var showsInDock = false

    private var panelController: IslandPanelController!
    private var hoverTracker: HoverTracker!
    private var clipboardMonitor: ClipboardMonitor!
    private var mediaController: MediaRemoteController!

    private let islandState = IslandState()
    private let appSettings = AppSettings.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        ClipboardStore.shared.applyLimits(
            maxText: appSettings.maxTextItems,
            maxImages: appSettings.maxImageItems
        )

        // Стартовая вкладка до первого открытия.
        islandState.applyStartupScreen(from: appSettings)

        mediaController = MediaRemoteController()
        mediaController.onUpdate = { [weak self] info in
            DispatchQueue.main.async {
                self?.islandState.nowPlaying = info
            }
        }
        mediaController.start()

        clipboardMonitor = ClipboardMonitor(store: ClipboardStore.shared)
        clipboardMonitor.onChange = { [weak self] kind in
            DispatchQueue.main.async {
                guard let self else { return }
                NSLog("[MacIsland][Pulse] trigger from monitor kind=%@ main=%d",
                      kind as NSString, Thread.isMainThread ? 1 : 0)
                self.islandState.reloadClipboard()
                // Вспышка только для внешней записи (own write не доходит сюда).
                self.panelController?.flashClipboardArrival(kind: kind)
            }
        }
        clipboardMonitor.start()
        islandState.reloadClipboard()
        islandState.reloadNotes()

        panelController = IslandPanelController(
            state: islandState,
            settings: appSettings,
            media: mediaController,
            onCopyText: { [weak self] item in
                ClipboardStore.shared.writeTextToPasteboard(item)
                self?.clipboardMonitor.acknowledgeOwnWrite()
            },
            onReorderText: { [weak self] item in
                ClipboardStore.shared.bumpTextToTop(item)
                self?.islandState.reloadClipboard()
            },
            onCopyImage: { [weak self] item in
                ClipboardStore.shared.writeImageToPasteboard(item)
                self?.clipboardMonitor.acknowledgeOwnWrite()
            },
            onReorderImage: { [weak self] item in
                ClipboardStore.shared.bumpImageToTop(item)
                self?.islandState.reloadClipboard()
            },
            onDeleteText: { [weak self] item in
                ClipboardStore.shared.deleteText(item)
                self?.islandState.reloadClipboard()
            },
            onDeleteImage: { [weak self] item in
                ClipboardStore.shared.deleteImage(item)
                self?.islandState.reloadClipboard()
            },
            onAddNote: { [weak self] text in
                NotesStore.shared.add(text)
                self?.islandState.reloadNotes()
            },
            onUpdateNote: { [weak self] item, text in
                NotesStore.shared.update(item, text: text)
                self?.islandState.reloadNotes()
            },
            onDeleteNote: { [weak self] item in
                NotesStore.shared.delete(item)
                self?.islandState.reloadNotes()
            }
        )
        panelController.onHoverChange = { [weak self] inside in
            self?.hoverTracker?.setPointerInsidePanel(inside)
        }

        hoverTracker = HoverTracker()
        hoverTracker.panelFrameProvider = { [weak self] in
            self?.panelController.panelScreenFrame
        }
        hoverTracker.onShouldExpand = { [weak self] openNotes in
            self?.panelController.showExpanded(openNotes: openNotes)
        }
        hoverTracker.onShouldCollapse = { [weak self] in
            self?.panelController.hideExpanded()
        }
        hoverTracker.start()

        NotificationCenter.default.addObserver(
            forName: .macIslandShowPanel,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.panelController.showExpanded()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hoverTracker?.stop()
        clipboardMonitor?.stop()
        mediaController?.stop()
    }

    func setShowsInDock(_ show: Bool) {
        showsInDock = show
        NSApp.setActivationPolicy(show ? .regular : .accessory)
        if show {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
