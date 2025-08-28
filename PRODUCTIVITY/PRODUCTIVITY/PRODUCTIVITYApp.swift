import SwiftUI

@main
struct PRODUC: App {
    @StateObject private var store = TaskStore()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(store)
        }
    }
}
