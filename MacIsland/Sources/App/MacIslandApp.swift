import AppKit
import SwiftUI

@main
struct MacIslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Меню-бар иконка; основное окно — NSPanel из AppDelegate.
        MenuBarExtra("Mac Island", systemImage: "capsule.portrait.fill") {
            Button("Показать панель") {
                NotificationCenter.default.post(name: .macIslandShowPanel, object: nil)
            }
            Divider()
            Toggle("Показывать в Dock", isOn: Binding(
                get: { appDelegate.showsInDock },
                set: { appDelegate.setShowsInDock($0) }
            ))
            Divider()
            Button("Выйти") {
                NSApp.terminate(nil)
            }
        }
    }
}

extension Notification.Name {
    static let macIslandShowPanel = Notification.Name("dev.nursat.MacIsland.showPanel")
}
