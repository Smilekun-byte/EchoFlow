import SwiftUI
import SwiftData

@main
struct EchoFlowApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [ConversationRecord.self, Folder.self])
    }
}
