import SwiftUI
import CoreAudio

@main
struct SampleRateMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView() // no UI needed
        }
    }
}
