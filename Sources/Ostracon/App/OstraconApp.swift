import SwiftUI

@main
struct OstraconApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel.makeDefault()

    var body: some Scene {
        Window("Ostracon", id: "main") {
            ContentView()
                .environment(model)
        }
        .defaultSize(width: 1040, height: 720)
        .commands {
            TaskCommands(model: model)
        }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}
