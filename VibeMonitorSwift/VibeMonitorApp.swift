import SwiftUI

@main
struct VibeMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            // Settings is now opened via .sheet in PopoverView
            // This empty Settings scene prevents macOS from showing a default window
            EmptyView()
        }
    }
}
